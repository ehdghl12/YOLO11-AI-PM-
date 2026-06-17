import Foundation
import SwiftUI

struct BoundingBoxOverlay: View {
    let imageSize: CGSize
    let detections: [DetectionResult]
    let isDebugMode: Bool

    private var visibleDetections: [DetectionResult] {
        detections.filter { !$0.detectedClass.isIgnoredByAppPolicy }
    }

    var body: some View {
        GeometryReader { geometry in
            let imageRect = aspectFitRect(
                imageSize: imageSize,
                containerSize: geometry.size
            )

            ZStack(alignment: .topLeading) {
                ForEach(visibleDetections) { detection in
                    let rect = displayRect(
                        for: detection.boundingBox.rect,
                        imageRect: imageRect
                    )
                    let color = DetectionPalette.color(for: detection.detectedClass)

                    RoundedRectangle(cornerRadius: 3)
                        .stroke(color, lineWidth: 2)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)

                    Text(labelText(for: detection))
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(color.opacity(0.92), in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(.white)
                        .position(
                            x: rect.minX + min(max(rect.width / 2, 44), max(rect.width - 44, 44)),
                            y: max(rect.minY - 11, imageRect.minY + 11)
                        )
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    private func aspectFitRect(imageSize: CGSize, containerSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, containerSize.width > 0, containerSize.height > 0 else {
            return .zero
        }

        let scale = min(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        return CGRect(
            x: (containerSize.width - width) / 2,
            y: (containerSize.height - height) / 2,
            width: width,
            height: height
        )
    }

    private func displayRect(for boundingBox: CGRect, imageRect: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return .zero
        }

        let scaleX = imageRect.width / imageSize.width
        let scaleY = imageRect.height / imageSize.height

        return CGRect(
            x: imageRect.minX + boundingBox.minX * scaleX,
            y: imageRect.minY + boundingBox.minY * scaleY,
            width: boundingBox.width * scaleX,
            height: boundingBox.height * scaleY
        )
    }

    private func labelText(for detection: DetectionResult) -> String {
        if isDebugMode {
            return "\(detection.className) \(detection.confidence.decimalText)"
        }

        return "\(detection.detectedClass.displayName) \(detection.confidence.percentText)"
    }
}

enum DetectionPalette {
    static func color(for detectedClass: DetectionClass) -> Color {
        switch detectedClass {
        case .kickboard:
            return .green
        case .manhole:
            return .blue
        case .fireHydrant:
            return .red
        case .bollard:
            return .orange
        case .tactilePaving:
            return .purple
        }
    }
}

private extension Double {
    var percentText: String {
        "\(Int((self * 100).rounded()))%"
    }

    var decimalText: String {
        String(format: "%.4f", self)
    }
}
