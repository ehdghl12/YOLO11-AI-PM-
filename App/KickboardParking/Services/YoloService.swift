import CoreGraphics
import CoreML
import Foundation
import UIKit
import Vision

enum YoloServiceError: LocalizedError {
    case modelNotFound
    case cgImageCreationFailed
    case unsupportedOutput
    case invalidOutputShape([Int])
    case visionFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "CoreML 모델을 찾을 수 없습니다."
        case .cgImageCreationFailed:
            return "촬영 이미지를 분석 가능한 형식으로 변환하지 못했습니다."
        case .unsupportedOutput:
            return "모델 출력 형식을 해석하지 못했습니다."
        case .invalidOutputShape(let shape):
            return "YOLO 출력 텐서 형태가 예상과 다릅니다: \(shape)"
        case .visionFailed(let message):
            return "CoreML 추론에 실패했습니다. \(message)"
        }
    }
}

final class ConfidenceThresholdProvider {
    private static var thresholds: [String: Float] = [
        DetectionClass.kickboard.rawValue: 0.25,
        DetectionClass.manhole.rawValue: 0.10,
        DetectionClass.fireHydrant.rawValue: 0.005,
        DetectionClass.bollard.rawValue: 0.005,
        DetectionClass.tactilePaving.rawValue: 0.01
    ]

    static func configure(thresholds newThresholds: [String: Float]) {
        thresholds.merge(newThresholds) { _, newValue in newValue }
    }

    static func threshold(for className: String) -> Float {
        thresholds[className] ?? 0.25
    }
}

final class YoloService {
    private static let modelName = "best"
    private static let debugConfidenceThreshold = 0.001
    private let labels = DetectionClass.allCases
    private let iouThreshold: Double
    private let maxDetections: Int
    private let visionModel: VNCoreMLModel
    private let modelInputSize: CGSize
    private let queue = DispatchQueue(label: "com.donghoe.kickboard.yolo")

    init(
        iouThreshold: Double = 0.45,
        maxDetections: Int = 100
    ) throws {
        self.iouThreshold = iouThreshold
        self.maxDetections = maxDetections

        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all

        let loadedModel = try Self.loadModel(named: Self.modelName, configuration: configuration)
        self.visionModel = try VNCoreMLModel(for: loadedModel)
        self.modelInputSize = Self.inputSize(for: loadedModel) ?? CGSize(width: 640, height: 640)
    }

    func detect(in image: UIImage, debugMode: Bool = false) async throws -> [DetectionResult] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let detections = try self.performDetection(in: image, debugMode: debugMode)
                    continuation.resume(returning: detections)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func performDetection(in image: UIImage, debugMode: Bool) throws -> [DetectionResult] {
        let normalizedImage = image.normalizedForAnalysis
        guard let cgImage = normalizedImage.cgImage else {
            throw YoloServiceError.cgImageCreationFailed
        }

        let request = VNCoreMLRequest(model: visionModel)
        request.imageCropAndScaleOption = .scaleFill

        let handler = VNImageRequestHandler(
            cgImage: cgImage,
            orientation: .up,
            options: [:]
        )

        do {
            try handler.perform([request])
        } catch {
            throw YoloServiceError.visionFailed(error.localizedDescription)
        }

        guard let observations = request.results, !observations.isEmpty else {
            return []
        }

        let detections: [DetectionResult]
        if let recognizedObjects = observations as? [VNRecognizedObjectObservation] {
            detections = parseRecognizedObjects(
                recognizedObjects,
                imageSize: normalizedImage.pixelSize,
                debugMode: debugMode
            )
        } else {
            guard let multiArray = observations
                .compactMap({ ($0 as? VNCoreMLFeatureValueObservation)?.featureValue.multiArrayValue })
                .first
            else {
                throw YoloServiceError.unsupportedOutput
            }

            let rawDetections = try parseRawYoloOutput(
                multiArray,
                imageSize: normalizedImage.pixelSize,
                debugMode: debugMode
            )
            detections = debugMode ? rawDetections : nonMaxSuppression(rawDetections)
        }

        logDetections(detections)
        return detections
    }

    private static func loadModel(named name: String, configuration: MLModelConfiguration) throws -> MLModel {
        if let compiledURL = Bundle.main.url(forResource: name, withExtension: "mlmodelc") {
            return try MLModel(contentsOf: compiledURL, configuration: configuration)
        }

        if let packageURL = Bundle.main.url(forResource: name, withExtension: "mlpackage") {
            let compiledURL = try MLModel.compileModel(at: packageURL)
            return try MLModel(contentsOf: compiledURL, configuration: configuration)
        }

        throw YoloServiceError.modelNotFound
    }

    private static func inputSize(for model: MLModel) -> CGSize? {
        let imageInput = model.modelDescription.inputDescriptionsByName.values.first { $0.type == .image }
        guard let constraint = imageInput?.imageConstraint else {
            return nil
        }

        return CGSize(width: constraint.pixelsWide, height: constraint.pixelsHigh)
    }

    private func parseRecognizedObjects(
        _ observations: [VNRecognizedObjectObservation],
        imageSize: CGSize,
        debugMode: Bool
    ) -> [DetectionResult] {
        observations.compactMap { observation in
            guard let label = observation.labels.first,
                  let detectedClass = DetectionClass(rawValue: label.identifier)
            else {
                return nil
            }

            let threshold = threshold(for: detectedClass, debugMode: debugMode)
            guard Double(label.confidence) > threshold else {
                return nil
            }

            let rect = VNImageRectForNormalizedRect(
                observation.boundingBox,
                Int(imageSize.width),
                Int(imageSize.height)
            )
            let topLeftRect = CGRect(
                x: rect.minX,
                y: imageSize.height - rect.maxY,
                width: rect.width,
                height: rect.height
            )

            return DetectionResult(
                detectedClass: detectedClass,
                confidence: Double(label.confidence),
                boundingBox: topLeftRect.clamped(to: imageSize).boundingBoxModel
            )
        }
    }

    private func parseRawYoloOutput(
        _ multiArray: MLMultiArray,
        imageSize: CGSize,
        debugMode: Bool
    ) throws -> [DetectionResult] {
        let shape = multiArray.shape.map(\.intValue)
        let featureCount = 4 + labels.count
        let layout = try YoloOutputLayout(shape: shape, featureCount: featureCount)

        // Ultralytics nms=false exports raw predictions. This keeps the parser
        // flexible for both [1, 9, 8400] and [1, 8400, 9] style outputs.
        var detections: [DetectionResult] = []
        detections.reserveCapacity(min(layout.predictionCount, maxDetections * 4))

        for predictionIndex in 0..<layout.predictionCount {
            var bestClassIndex = 0
            var bestConfidence = 0.0

            for classIndex in 0..<labels.count {
                let confidence = multiArray.doubleValue(
                    at: layout.indexes(featureIndex: 4 + classIndex, predictionIndex: predictionIndex)
                )

                if confidence > bestConfidence {
                    bestConfidence = confidence
                    bestClassIndex = classIndex
                }
            }

            guard let detectedClass = DetectionClass.fromModelIndex(bestClassIndex)
            else {
                continue
            }

            let threshold = threshold(for: detectedClass, debugMode: debugMode)
            guard bestConfidence > threshold else {
                continue
            }

            let centerX = multiArray.doubleValue(at: layout.indexes(featureIndex: 0, predictionIndex: predictionIndex))
            let centerY = multiArray.doubleValue(at: layout.indexes(featureIndex: 1, predictionIndex: predictionIndex))
            let width = multiArray.doubleValue(at: layout.indexes(featureIndex: 2, predictionIndex: predictionIndex))
            let height = multiArray.doubleValue(at: layout.indexes(featureIndex: 3, predictionIndex: predictionIndex))

            let rect = convertYoloBoxToImageRect(
                centerX: centerX,
                centerY: centerY,
                width: width,
                height: height,
                imageSize: imageSize
            )

            guard rect.width > 1, rect.height > 1 else {
                continue
            }

            detections.append(
                DetectionResult(
                    detectedClass: detectedClass,
                    confidence: bestConfidence,
                    boundingBox: rect.clamped(to: imageSize).boundingBoxModel
                )
            )
        }

        return detections
    }

    private func convertYoloBoxToImageRect(
        centerX: Double,
        centerY: Double,
        width: Double,
        height: Double,
        imageSize: CGSize
    ) -> CGRect {
        // Most YOLO CoreML exports return 640-space xywh values, but normalized
        // outputs are handled too so the service is safer when the model changes.
        let looksNormalized = [centerX, centerY, width, height].allSatisfy { abs($0) <= 1.5 }
        let inputWidth = looksNormalized ? 1.0 : Double(modelInputSize.width)
        let inputHeight = looksNormalized ? 1.0 : Double(modelInputSize.height)

        let x = (centerX - width / 2) / inputWidth * Double(imageSize.width)
        let y = (centerY - height / 2) / inputHeight * Double(imageSize.height)
        let rectWidth = width / inputWidth * Double(imageSize.width)
        let rectHeight = height / inputHeight * Double(imageSize.height)

        return CGRect(x: x, y: y, width: rectWidth, height: rectHeight)
    }

    private func nonMaxSuppression(_ detections: [DetectionResult]) -> [DetectionResult] {
        // The provided model was exported with nms=false, so duplicate boxes are
        // reduced here after applying the per-class confidence thresholds.
        var selected: [DetectionResult] = []
        let sorted = detections.sorted { $0.confidence > $1.confidence }

        for detection in sorted {
            let hasOverlap = selected.contains { selectedDetection in
                selectedDetection.detectedClass == detection.detectedClass &&
                    selectedDetection.boundingBox.rect.iou(with: detection.boundingBox.rect) > iouThreshold
            }

            if !hasOverlap {
                selected.append(detection)
            }

            if selected.count >= maxDetections {
                break
            }
        }

        return selected
    }

    private func threshold(for detectedClass: DetectionClass, debugMode: Bool) -> Double {
        if debugMode {
            return Self.debugConfidenceThreshold
        }

        return Double(ConfidenceThresholdProvider.threshold(for: detectedClass.rawValue))
    }

    private func logDetections(_ detections: [DetectionResult]) {
        detections
            .filter { !$0.detectedClass.isIgnoredByAppPolicy }
            .forEach { detection in
                let box = detection.boundingBox
                print(
                    """
                    [\(detection.className)]
                    confidence: \(String(format: "%.6f", detection.confidence))
                    boundingBox: x=\(String(format: "%.1f", Double(box.x))), y=\(String(format: "%.1f", Double(box.y))), width=\(String(format: "%.1f", Double(box.width))), height=\(String(format: "%.1f", Double(box.height)))
                    """
                )
            }
    }
}

private struct YoloOutputLayout {
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
        guard nonSingletonAxes.count >= 2 else {
            throw YoloServiceError.invalidOutputShape(shape)
        }

        if let featureAxis = nonSingletonAxes.first(where: { $0.element == featureCount })?.offset,
           let predictionAxis = nonSingletonAxes.first(where: { $0.offset != featureAxis })?.offset {
            self.format = .channelFirst(featureAxis: featureAxis, predictionAxis: predictionAxis)
            self.predictionCount = shape[predictionAxis]
            return
        }

        if let featureAxis = nonSingletonAxes.last(where: { $0.element == featureCount })?.offset,
           let predictionAxis = nonSingletonAxes.last(where: { $0.offset != featureAxis })?.offset {
            self.format = .channelLast(predictionAxis: predictionAxis, featureAxis: featureAxis)
            self.predictionCount = shape[predictionAxis]
            return
        }

        throw YoloServiceError.invalidOutputShape(shape)
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

private extension MLMultiArray {
    func doubleValue(at indexes: [NSNumber]) -> Double {
        self[indexes].doubleValue
    }
}

private extension CGRect {
    var boundingBoxModel: BoundingBoxModel {
        BoundingBoxModel(x: minX, y: minY, width: width, height: height)
    }

    func clamped(to size: CGSize) -> CGRect {
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

    func iou(with other: CGRect) -> Double {
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
