import CoreGraphics
import Foundation

struct CrosswalkRegion: Identifiable, Equatable {
    let id = UUID()
    let confidence: Double
    let boundingBox: BoundingBoxModel
    let polygon: [CGPoint]
    let maskPixelCount: Int

    func contains(_ point: CGPoint) -> Bool {
        guard polygon.count >= 3 else {
            return false
        }

        var isInside = false
        var previousIndex = polygon.count - 1

        for currentIndex in polygon.indices {
            let current = polygon[currentIndex]
            let previous = polygon[previousIndex]
            let crossesY = (current.y > point.y) != (previous.y > point.y)

            if crossesY {
                let denominator = previous.y - current.y
                guard abs(denominator) > .ulpOfOne else {
                    previousIndex = currentIndex
                    continue
                }

                let projectedX = (previous.x - current.x) * (point.y - current.y) / denominator + current.x
                if point.x < projectedX {
                    isInside.toggle()
                }
            }

            previousIndex = currentIndex
        }

        return isInside
    }
}

struct CrosswalkDebugInfo: Equatable {
    let crosswalkCount: Int
    let polygonPointCounts: [Int]
    let kickboardCenter: CGPoint?
    let isInsideCrosswalk: Bool
}
