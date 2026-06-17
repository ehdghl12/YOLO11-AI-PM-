import SwiftUI

struct CrosswalkMaskOverlay: View {
    let imageSize: CGSize
    let regions: [CrosswalkRegion]

    var body: some View {
        GeometryReader { geometry in
            let imageRect = aspectFitRect(
                imageSize: imageSize,
                containerSize: geometry.size
            )

            ZStack {
                ForEach(regions) { region in
                    let points = region.polygon.map { displayPoint(for: $0, imageRect: imageRect) }

                    if points.count >= 3 {
                        Path { path in
                            path.move(to: points[0])
                            points.dropFirst().forEach { path.addLine(to: $0) }
                            path.closeSubpath()
                        }
                        .fill(.cyan.opacity(0.28))

                        Path { path in
                            path.move(to: points[0])
                            points.dropFirst().forEach { path.addLine(to: $0) }
                            path.closeSubpath()
                        }
                        .stroke(.cyan, lineWidth: 3)
                    }
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

    private func displayPoint(for point: CGPoint, imageRect: CGRect) -> CGPoint {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return .zero
        }

        return CGPoint(
            x: imageRect.minX + point.x / imageSize.width * imageRect.width,
            y: imageRect.minY + point.y / imageSize.height * imageRect.height
        )
    }
}
