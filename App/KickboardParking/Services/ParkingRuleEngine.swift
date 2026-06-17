import CoreGraphics
import Foundation

protocol ParkingDistanceCalculating {
    func distance(from first: BoundingBoxModel, to second: BoundingBoxModel) -> Double
}

struct CenterDistanceCalculator: ParkingDistanceCalculating {
    func distance(from first: BoundingBoxModel, to second: BoundingBoxModel) -> Double {
        let firstCenter = first.center
        let secondCenter = second.center
        let dx = firstCenter.x - secondCenter.x
        let dy = firstCenter.y - secondCenter.y
        return sqrt(Double(dx * dx + dy * dy))
    }
}

struct ParkingRuleEngine {
    private let confidenceThreshold: Double
    private let distanceCalculator: ParkingDistanceCalculating

    // Final parking restriction policy: tactile paving, fire hydrants, and manholes only.
    private let restrictedThresholds: [DetectionClass: Double] = [
        .tactilePaving: 0.8,
        .fireHydrant: 1.1,
        .manhole: 0.7
    ]

    // These thresholds apply only to parking decisions, not debug visualization.
    private let ruleConfidenceThresholds: [DetectionClass: Double] = [
        .tactilePaving: 0.01,
        .manhole: 0.05,
        .fireHydrant: 0.05
    ]

    init(
        confidenceThreshold: Double = 0.0,
        distanceCalculator: ParkingDistanceCalculating = CenterDistanceCalculator()
    ) {
        self.confidenceThreshold = confidenceThreshold
        self.distanceCalculator = distanceCalculator
    }

    func evaluate(
        detections: [DetectionResult],
        crosswalkRegions: [CrosswalkRegion] = []
    ) -> ParkingAssessment {
        // The kickboard is already filtered by the decision-stage detection pass.
        guard let kickboard = detections
            .filter({ $0.detectedClass == .kickboard && $0.confidence >= confidenceThreshold })
            .max(by: { $0.confidence < $1.confidence })
        else {
            return .kickboardMissing
        }

        let kickboardHeight = Double(kickboard.boundingBox.height)
        guard kickboardHeight > 0 else {
            return .kickboardMissing
        }

        let kickboardCenter = kickboard.boundingBox.center
        let isInsideCrosswalk = crosswalkRegions.contains { $0.contains(kickboardCenter) }
        let crosswalkDebugInfo = CrosswalkDebugInfo(
            crosswalkCount: crosswalkRegions.count,
            polygonPointCounts: crosswalkRegions.map(\.polygon.count),
            kickboardCenter: kickboardCenter,
            isInsideCrosswalk: isInsideCrosswalk
        )

        var violations: [ParkingViolation] = isInsideCrosswalk ? [.crosswalk()] : []

        // Steps 3-7: compare each restricted object using the closest detection,
        // normalized by kickboard height to reduce camera-distance bias.
        violations.append(contentsOf: restrictedThresholds.compactMap { detectedClass, threshold -> ParkingViolation? in
            guard let ruleConfidenceThreshold = ruleConfidenceThresholds[detectedClass] else {
                return nil
            }

            let nearestDistance = detections
                .filter {
                    $0.detectedClass == detectedClass &&
                        $0.confidence >= ruleConfidenceThreshold
                }
                .map { distanceCalculator.distance(from: kickboard.boundingBox, to: $0.boundingBox) / kickboardHeight }
                .min()

            guard let normalizedDistance = nearestDistance else {
                return nil
            }

            guard normalizedDistance <= threshold else {
                return nil
            }

            return .proximity(
                detectedClass: detectedClass,
                normalizedDistance: normalizedDistance,
                threshold: threshold
            )
        })

        violations.sort { $0.priority < $1.priority }

        if violations.isEmpty {
            return ParkingAssessment(
                status: .allowed,
                message: "주차 가능 ✅",
                violations: [],
                crosswalkDebugInfo: crosswalkDebugInfo
            )
        }

        return ParkingAssessment(
            status: .prohibited,
            message: "주차 불가 ❌",
            violations: violations,
            crosswalkDebugInfo: crosswalkDebugInfo
        )
    }
}
