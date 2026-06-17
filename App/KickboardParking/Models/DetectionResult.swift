import CoreGraphics
import Foundation

enum DetectionClass: String, CaseIterable, Identifiable {
    case kickboard
    case manhole
    case fireHydrant = "fire_hydrant"
    case bollard
    case tactilePaving = "tactile_paving"

    var id: String { rawValue }

    // Bollard remains a model output class, but field policy no longer uses it
    // for parking restriction decisions or result/debug presentation.
    static let parkingRestrictionClasses: [DetectionClass] = [
        .tactilePaving,
        .fireHydrant,
        .manhole
    ]

    static let appVisibleClasses: [DetectionClass] = [
        .kickboard,
        .manhole,
        .fireHydrant,
        .tactilePaving
    ]

    var isIgnoredByAppPolicy: Bool {
        self == .bollard
    }

    var displayName: String {
        switch self {
        case .kickboard:
            return "킥보드"
        case .manhole:
            return "맨홀"
        case .fireHydrant:
            return "소화전"
        case .bollard:
            return "볼라드"
        case .tactilePaving:
            return "점자블록"
        }
    }

    static func fromModelIndex(_ index: Int) -> DetectionClass? {
        switch index {
        case 0:
            return .kickboard
        case 1:
            return .manhole
        case 2:
            return .fireHydrant
        case 3:
            return .bollard
        case 4:
            return .tactilePaving
        default:
            return nil
        }
    }
}

struct BoundingBoxModel: Equatable {
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat

    var rect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    var center: CGPoint {
        CGPoint(x: x + width / 2, y: y + height / 2)
    }
}

struct DetectionResult: Identifiable, Equatable {
    let id = UUID()
    let detectedClass: DetectionClass
    let confidence: Double
    let boundingBox: BoundingBoxModel

    var className: String {
        detectedClass.rawValue
    }
}
