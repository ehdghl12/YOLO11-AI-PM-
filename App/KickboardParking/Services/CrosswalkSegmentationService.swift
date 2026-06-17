import CoreGraphics
import CoreML
import Foundation
import UIKit
import Vision

enum CrosswalkSegmentationError: LocalizedError {
    case modelNotFound
    case cgImageCreationFailed
    case unsupportedOutput
    case invalidOutputShape([Int])
    case visionFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "횡단보도 세그멘테이션 모델을 찾을 수 없습니다."
        case .cgImageCreationFailed:
            return "촬영 이미지를 횡단보도 분석 형식으로 변환하지 못했습니다."
        case .unsupportedOutput:
            return "횡단보도 세그멘테이션 출력 형식을 해석하지 못했습니다."
        case .invalidOutputShape(let shape):
            return "횡단보도 세그멘테이션 출력 텐서 형태가 예상과 다릅니다: \(shape)"
        case .visionFailed(let message):
            return "횡단보도 세그멘테이션 추론에 실패했습니다. \(message)"
        }
    }
}

final class CrosswalkSegmentationService {
    private static let modelName = "crosswalk_segmenter"
    private static let classConfidenceThreshold = 0.10
    private static let debugConfidenceThreshold = 0.001
    private static let maskThreshold = 0.5
    fileprivate static let maskCoefficientCount = 32
    private static let classCount = 1

    private let iouThreshold: Double
    private let maxRegions: Int
    private let visionModel: VNCoreMLModel
    private let modelInputSize: CGSize
    private let queue = DispatchQueue(label: "com.donghoe.kickboard.crosswalk")

    init(
        iouThreshold: Double = 0.45,
        maxRegions: Int = 20
    ) throws {
        self.iouThreshold = iouThreshold
        self.maxRegions = maxRegions

        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all

        let loadedModel = try Self.loadModel(named: Self.modelName, configuration: configuration)
        self.visionModel = try VNCoreMLModel(for: loadedModel)
        self.modelInputSize = Self.inputSize(for: loadedModel) ?? CGSize(width: 640, height: 640)
    }

    func segment(in image: UIImage, debugMode: Bool = false) async throws -> [CrosswalkRegion] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let regions = try self.performSegmentation(in: image, debugMode: debugMode)
                    continuation.resume(returning: regions)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func performSegmentation(in image: UIImage, debugMode: Bool) throws -> [CrosswalkRegion] {
        let normalizedImage = image.normalizedForAnalysis
        guard let cgImage = normalizedImage.cgImage else {
            throw CrosswalkSegmentationError.cgImageCreationFailed
        }

        let request = VNCoreMLRequest(model: visionModel)
        request.imageCropAndScaleOption = .scaleFill

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])

        do {
            try handler.perform([request])
        } catch {
            throw CrosswalkSegmentationError.visionFailed(error.localizedDescription)
        }

        guard let observations = request.results as? [VNCoreMLFeatureValueObservation] else {
            return []
        }

        let outputs = observations.reduce(into: [String: MLMultiArray]()) { partialResult, observation in
            if let multiArray = observation.featureValue.multiArrayValue {
                partialResult[observation.featureName] = multiArray
            }
        }

        guard let predictionOutput = outputs["var_1323"] ?? outputs.values.first(where: {
            $0.shape.map(\.intValue).contains(Self.featureCount)
        }) else {
            throw CrosswalkSegmentationError.unsupportedOutput
        }

        guard let prototypeOutput = outputs["var_1361"] ?? outputs.values.first(where: {
            $0.shape.count == 4 && $0.shape.map(\.intValue).contains(Self.maskCoefficientCount)
        }) else {
            throw CrosswalkSegmentationError.unsupportedOutput
        }

        return try parseSegmentationOutput(
            predictions: predictionOutput,
            prototypes: prototypeOutput,
            imageSize: normalizedImage.pixelSize,
            debugMode: debugMode
        )
    }

    private static var featureCount: Int {
        4 + classCount + maskCoefficientCount
    }

    private static func loadModel(named name: String, configuration: MLModelConfiguration) throws -> MLModel {
        if let compiledURL = Bundle.main.url(forResource: name, withExtension: "mlmodelc") {
            return try MLModel(contentsOf: compiledURL, configuration: configuration)
        }

        if let packageURL = Bundle.main.url(forResource: name, withExtension: "mlpackage") {
            let compiledURL = try MLModel.compileModel(at: packageURL)
            return try MLModel(contentsOf: compiledURL, configuration: configuration)
        }

        throw CrosswalkSegmentationError.modelNotFound
    }

    private static func inputSize(for model: MLModel) -> CGSize? {
        let imageInput = model.modelDescription.inputDescriptionsByName.values.first { $0.type == .image }
        guard let constraint = imageInput?.imageConstraint else {
            return nil
        }

        return CGSize(width: constraint.pixelsWide, height: constraint.pixelsHigh)
    }

    private func parseSegmentationOutput(
        predictions: MLMultiArray,
        prototypes: MLMultiArray,
        imageSize: CGSize,
        debugMode: Bool
    ) throws -> [CrosswalkRegion] {
        let predictionShape = predictions.shape.map(\.intValue)
        let predictionLayout = try SegmentationPredictionLayout(
            shape: predictionShape,
            featureCount: Self.featureCount
        )
        let prototypeLayout = try PrototypeMaskLayout(shape: prototypes.shape.map(\.intValue))
        let threshold = debugMode ? Self.debugConfidenceThreshold : Self.classConfidenceThreshold

        var candidates: [CrosswalkCandidate] = []

        for predictionIndex in 0..<predictionLayout.predictionCount {
            let confidence = predictions.crosswalkDoubleValue(
                at: predictionLayout.indexes(featureIndex: 4, predictionIndex: predictionIndex)
            )

            guard confidence > threshold else {
                continue
            }

            let centerX = predictions.crosswalkDoubleValue(at: predictionLayout.indexes(featureIndex: 0, predictionIndex: predictionIndex))
            let centerY = predictions.crosswalkDoubleValue(at: predictionLayout.indexes(featureIndex: 1, predictionIndex: predictionIndex))
            let width = predictions.crosswalkDoubleValue(at: predictionLayout.indexes(featureIndex: 2, predictionIndex: predictionIndex))
            let height = predictions.crosswalkDoubleValue(at: predictionLayout.indexes(featureIndex: 3, predictionIndex: predictionIndex))

            let rect = convertYoloBoxToImageRect(
                centerX: centerX,
                centerY: centerY,
                width: width,
                height: height,
                imageSize: imageSize
            ).crosswalkClamped(to: imageSize)

            guard rect.width > 1, rect.height > 1 else {
                continue
            }

            let coefficients = (0..<Self.maskCoefficientCount).map { coefficientIndex in
                predictions.crosswalkDoubleValue(
                    at: predictionLayout.indexes(
                        featureIndex: 4 + Self.classCount + coefficientIndex,
                        predictionIndex: predictionIndex
                    )
                )
            }

            candidates.append(
                CrosswalkCandidate(
                    confidence: confidence,
                    rect: rect,
                    coefficients: coefficients
                )
            )
        }

        let selectedCandidates = debugMode ? candidates.sorted { $0.confidence > $1.confidence } : nonMaxSuppression(candidates)
        return selectedCandidates.prefix(maxRegions).compactMap { candidate in
            buildRegion(
                from: candidate,
                prototypes: prototypes,
                layout: prototypeLayout,
                imageSize: imageSize
            )
        }
    }

    private func buildRegion(
        from candidate: CrosswalkCandidate,
        prototypes: MLMultiArray,
        layout: PrototypeMaskLayout,
        imageSize: CGSize
    ) -> CrosswalkRegion? {
        var mask = Array(repeating: false, count: layout.width * layout.height)
        var maskPixelCount = 0

        let protoRect = CGRect(
            x: candidate.rect.minX / imageSize.width * CGFloat(layout.width),
            y: candidate.rect.minY / imageSize.height * CGFloat(layout.height),
            width: candidate.rect.width / imageSize.width * CGFloat(layout.width),
            height: candidate.rect.height / imageSize.height * CGFloat(layout.height)
        )

        for y in 0..<layout.height {
            for x in 0..<layout.width {
                let protoPoint = CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)
                guard protoRect.contains(protoPoint) else {
                    continue
                }

                var value = 0.0
                for channel in 0..<min(layout.channels, candidate.coefficients.count) {
                    value += candidate.coefficients[channel] * prototypes.crosswalkDoubleValue(at: layout.indexes(channel: channel, x: x, y: y))
                }

                guard sigmoid(value) >= Self.maskThreshold else {
                    continue
                }

                mask[y * layout.width + x] = true
                maskPixelCount += 1
            }
        }

        let polygon = extractPolygon(
            from: mask,
            width: layout.width,
            height: layout.height,
            fallbackRect: candidate.rect,
            imageSize: imageSize
        )

        guard polygon.count >= 3 else {
            return nil
        }

        return CrosswalkRegion(
            confidence: candidate.confidence,
            boundingBox: candidate.rect.crosswalkBoundingBoxModel,
            polygon: polygon,
            maskPixelCount: maskPixelCount
        )
    }

    private func extractPolygon(
        from mask: [Bool],
        width: Int,
        height: Int,
        fallbackRect: CGRect,
        imageSize: CGSize
    ) -> [CGPoint] {
        var boundaryPoints: [CGPoint] = []

        for y in 0..<height {
            for x in 0..<width where mask[y * width + x] {
                if isBoundaryPixel(mask: mask, x: x, y: y, width: width, height: height) {
                    boundaryPoints.append(
                        CGPoint(
                            x: (CGFloat(x) + 0.5) / CGFloat(width) * imageSize.width,
                            y: (CGFloat(y) + 0.5) / CGFloat(height) * imageSize.height
                        )
                    )
                }
            }
        }

        guard boundaryPoints.count >= 3 else {
            return fallbackPolygon(for: fallbackRect)
        }

        return convexHull(points: boundaryPoints)
    }

    private func isBoundaryPixel(mask: [Bool], x: Int, y: Int, width: Int, height: Int) -> Bool {
        let offsets = [(-1, 0), (1, 0), (0, -1), (0, 1)]

        for offset in offsets {
            let nextX = x + offset.0
            let nextY = y + offset.1

            guard nextX >= 0, nextY >= 0, nextX < width, nextY < height else {
                return true
            }

            if !mask[nextY * width + nextX] {
                return true
            }
        }

        return false
    }

    private func fallbackPolygon(for rect: CGRect) -> [CGPoint] {
        [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY)
        ]
    }

    private func convexHull(points: [CGPoint]) -> [CGPoint] {
        let sortedPoints = points.sorted {
            if $0.x == $1.x {
                return $0.y < $1.y
            }
            return $0.x < $1.x
        }

        guard sortedPoints.count > 2 else {
            return sortedPoints
        }

        var lower: [CGPoint] = []
        for point in sortedPoints {
            while lower.count >= 2 && cross(lower[lower.count - 2], lower[lower.count - 1], point) <= 0 {
                lower.removeLast()
            }
            lower.append(point)
        }

        var upper: [CGPoint] = []
        for point in sortedPoints.reversed() {
            while upper.count >= 2 && cross(upper[upper.count - 2], upper[upper.count - 1], point) <= 0 {
                upper.removeLast()
            }
            upper.append(point)
        }

        lower.removeLast()
        upper.removeLast()
        return lower + upper
    }

    private func cross(_ origin: CGPoint, _ first: CGPoint, _ second: CGPoint) -> CGFloat {
        (first.x - origin.x) * (second.y - origin.y) - (first.y - origin.y) * (second.x - origin.x)
    }

    private func convertYoloBoxToImageRect(
        centerX: Double,
        centerY: Double,
        width: Double,
        height: Double,
        imageSize: CGSize
    ) -> CGRect {
        let looksNormalized = [centerX, centerY, width, height].allSatisfy { abs($0) <= 1.5 }
        let inputWidth = looksNormalized ? 1.0 : Double(modelInputSize.width)
        let inputHeight = looksNormalized ? 1.0 : Double(modelInputSize.height)

        let x = (centerX - width / 2) / inputWidth * Double(imageSize.width)
        let y = (centerY - height / 2) / inputHeight * Double(imageSize.height)
        let rectWidth = width / inputWidth * Double(imageSize.width)
        let rectHeight = height / inputHeight * Double(imageSize.height)

        return CGRect(x: x, y: y, width: rectWidth, height: rectHeight)
    }

    private func nonMaxSuppression(_ candidates: [CrosswalkCandidate]) -> [CrosswalkCandidate] {
        var selected: [CrosswalkCandidate] = []
        let sorted = candidates.sorted { $0.confidence > $1.confidence }

        for candidate in sorted {
            let hasOverlap = selected.contains { selectedCandidate in
                selectedCandidate.rect.crosswalkIOU(with: candidate.rect) > iouThreshold
            }

            if !hasOverlap {
                selected.append(candidate)
            }

            if selected.count >= maxRegions {
                break
            }
        }

        return selected
    }

    private func sigmoid(_ value: Double) -> Double {
        1 / (1 + exp(-value))
    }
}

private struct CrosswalkCandidate {
    let confidence: Double
    let rect: CGRect
    let coefficients: [Double]
}

private struct SegmentationPredictionLayout {
    enum Format {
        case channelFirst(featureAxis: Int, predictionAxis: Int)
        case channelLast(predictionAxis: Int, featureAxis: Int)
    }

    let shape: [Int]
    let format: Format
    let predictionCount: Int

    init(shape: [Int], featureCount: Int) throws {
        self.shape = shape

        let nonSingletonAxes = shape.enumerated().filter { $0.element > 1 }
        guard let featureAxis = nonSingletonAxes.first(where: { $0.element == featureCount })?.offset,
              let predictionAxis = nonSingletonAxes.first(where: { $0.offset != featureAxis })?.offset
        else {
            throw CrosswalkSegmentationError.invalidOutputShape(shape)
        }

        if featureAxis < predictionAxis {
            self.format = .channelFirst(featureAxis: featureAxis, predictionAxis: predictionAxis)
        } else {
            self.format = .channelLast(predictionAxis: predictionAxis, featureAxis: featureAxis)
        }

        self.predictionCount = shape[predictionAxis]
    }

    func indexes(featureIndex: Int, predictionIndex: Int) -> [NSNumber] {
        var indexes = Array(repeating: 0, count: shape.count)

        switch format {
        case let .channelFirst(featureAxis, predictionAxis):
            indexes[featureAxis] = featureIndex
            indexes[predictionAxis] = predictionIndex
        case let .channelLast(predictionAxis, featureAxis):
            indexes[predictionAxis] = predictionIndex
            indexes[featureAxis] = featureIndex
        }

        return indexes.map { NSNumber(value: $0) }
    }
}

private struct PrototypeMaskLayout {
    enum Format {
        case channelFirst(channelAxis: Int, heightAxis: Int, widthAxis: Int)
        case channelLast(heightAxis: Int, widthAxis: Int, channelAxis: Int)
    }

    let shape: [Int]
    let format: Format
    let channels: Int
    let width: Int
    let height: Int

    init(shape: [Int]) throws {
        self.shape = shape

        guard shape.count == 4 else {
            throw CrosswalkSegmentationError.invalidOutputShape(shape)
        }

        if let channelAxis = shape.firstIndex(of: CrosswalkSegmentationService.maskCoefficientCount) {
            let spatialAxes = shape.indices.filter { $0 != channelAxis && shape[$0] > 1 }
            guard spatialAxes.count >= 2 else {
                throw CrosswalkSegmentationError.invalidOutputShape(shape)
            }

            if channelAxis < spatialAxes[0] {
                self.format = .channelFirst(channelAxis: channelAxis, heightAxis: spatialAxes[0], widthAxis: spatialAxes[1])
            } else {
                self.format = .channelLast(heightAxis: spatialAxes[0], widthAxis: spatialAxes[1], channelAxis: channelAxis)
            }

            self.channels = shape[channelAxis]
            self.height = shape[spatialAxes[0]]
            self.width = shape[spatialAxes[1]]
            return
        }

        throw CrosswalkSegmentationError.invalidOutputShape(shape)
    }

    func indexes(channel: Int, x: Int, y: Int) -> [NSNumber] {
        var indexes = Array(repeating: 0, count: shape.count)

        switch format {
        case let .channelFirst(channelAxis, heightAxis, widthAxis):
            indexes[channelAxis] = channel
            indexes[heightAxis] = y
            indexes[widthAxis] = x
        case let .channelLast(heightAxis, widthAxis, channelAxis):
            indexes[heightAxis] = y
            indexes[widthAxis] = x
            indexes[channelAxis] = channel
        }

        return indexes.map { NSNumber(value: $0) }
    }
}

private extension MLMultiArray {
    func crosswalkDoubleValue(at indexes: [NSNumber]) -> Double {
        self[indexes].doubleValue
    }
}

private extension CGRect {
    var crosswalkBoundingBoxModel: BoundingBoxModel {
        BoundingBoxModel(x: minX, y: minY, width: width, height: height)
    }

    func crosswalkClamped(to size: CGSize) -> CGRect {
        let minX = max(0, min(self.minX, size.width))
        let minY = max(0, min(self.minY, size.height))
        let maxX = max(0, min(self.maxX, size.width))
        let maxY = max(0, min(self.maxY, size.height))

        return CGRect(
            x: minX,
            y: minY,
            width: max(0, maxX - minX),
            height: max(0, maxY - minY)
        )
    }

    func crosswalkIOU(with other: CGRect) -> Double {
        let intersection = intersection(other)
        guard !intersection.isNull else {
            return 0
        }

        let intersectionArea = intersection.width * intersection.height
        let unionArea = width * height + other.width * other.height - intersectionArea
        guard unionArea > 0 else {
            return 0
        }

        return Double(intersectionArea / unionArea)
    }
}
