import CoreGraphics
import Foundation

enum ParkingStatus: Equatable {
    case allowed
    case prohibited
    case kickboardMissing
}

struct ParkingViolation: Identifiable, Equatable {
    let id = UUID()
    let kind: ParkingViolationKind
    let normalizedDistance: Double?
    let threshold: Double?

    static func crosswalk() -> ParkingViolation {
        ParkingViolation(
            kind: .crosswalk,
            normalizedDistance: nil,
            threshold: nil
        )
    }

    static func proximity(
        detectedClass: DetectionClass,
        normalizedDistance: Double,
        threshold: Double
    ) -> ParkingViolation {
        ParkingViolation(
            kind: .proximity(detectedClass),
            normalizedDistance: normalizedDistance,
            threshold: threshold
        )
    }

    var reasonText: String {
        kind.reasonText
    }

    var priority: Int {
        kind.priority
    }
}

enum ParkingViolationKind: Equatable {
    case crosswalk
    case proximity(DetectionClass)

    var reasonText: String {
        switch self {
        case .crosswalk:
            return "횡단보도 영역 내 주차"
        case .proximity(let detectedClass):
            return "\(detectedClass.displayName)과 너무 가까움"
        }
    }

    var priority: Int {
        switch self {
        case .crosswalk:
            return 0
        case .proximity(.tactilePaving):
            return 1
        case .proximity(.fireHydrant):
            return 2
        case .proximity(.manhole):
            return 3
        case .proximity:
            return 99
        }
    }
}

struct ParkingAssessment: Equatable {
    let status: ParkingStatus
    let message: String
    let violations: [ParkingViolation]
    let crosswalkDebugInfo: CrosswalkDebugInfo?

    var isParkingAllowed: Bool {
        status == .allowed
    }

    static let kickboardMissing = ParkingAssessment(
        status: .kickboardMissing,
        message: "킥보드를 인식하지 못했습니다.",
        violations: [],
        crosswalkDebugInfo: nil
    )
}
