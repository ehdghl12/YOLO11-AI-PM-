import Foundation
import UIKit

@MainActor
final class DetectionViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case running
        case completed
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var detections: [DetectionResult] = []
    @Published private(set) var crosswalkRegions: [CrosswalkRegion] = []
    @Published private(set) var assessment: ParkingAssessment?
    @Published private(set) var performanceStatistics: PerformanceStatistics?
    @Published var isDebugMode = false

    private let yoloServiceFactory: () throws -> YoloService
    private let crosswalkSegmentationServiceFactory: () throws -> CrosswalkSegmentationService
    private let ruleEngine: ParkingRuleEngine
    private let performanceMonitor: PerformanceMonitor
    private var hasStarted = false

    init(
        yoloServiceFactory: @escaping () throws -> YoloService = { try YoloService() },
        crosswalkSegmentationServiceFactory: @escaping () throws -> CrosswalkSegmentationService = { try CrosswalkSegmentationService() },
        ruleEngine: ParkingRuleEngine = ParkingRuleEngine(),
        performanceMonitor: PerformanceMonitor = .shared
    ) {
        self.yoloServiceFactory = yoloServiceFactory
        self.crosswalkSegmentationServiceFactory = crosswalkSegmentationServiceFactory
        self.ruleEngine = ruleEngine
        self.performanceMonitor = performanceMonitor
    }

    func runDetectionIfNeeded(on image: UIImage) async {
        guard !hasStarted else {
            return
        }

        hasStarted = true
        await runDetection(on: image)
    }

    func runDetection(on image: UIImage) async {
        state = .running
        assessment = nil
        detections = []
        crosswalkRegions = []
        performanceStatistics = nil

        do {
            let detectionService = try yoloServiceFactory()
            let detectionMeasurement = try await performanceMonitor.measure {
                try await detectionService.detect(in: image, debugMode: false)
            }
            let decisionDetections = detectionMeasurement.value.filter {
                !$0.detectedClass.isIgnoredByAppPolicy
            }

            if isDebugMode {
                detections = try await detectionService
                    .detect(in: image, debugMode: true)
                    .filter { !$0.detectedClass.isIgnoredByAppPolicy }
            } else {
                detections = decisionDetections
            }

            let crosswalkService = try crosswalkSegmentationServiceFactory()
            let segmentationMeasurement = try await performanceMonitor.measure {
                try await crosswalkService.segment(in: image, debugMode: false)
            }
            let decisionCrosswalkRegions = segmentationMeasurement.value

            if isDebugMode {
                crosswalkRegions = try await crosswalkService.segment(in: image, debugMode: true)
            } else {
                crosswalkRegions = decisionCrosswalkRegions
            }

            let parkingRuleMeasurement = performanceMonitor.measure {
                ruleEngine.evaluate(
                    detections: decisionDetections,
                    crosswalkRegions: decisionCrosswalkRegions
                )
            }
            assessment = parkingRuleMeasurement.value

            let memoryUsage = performanceMonitor.currentMemoryUsageMegabytes()
            performanceStatistics = performanceMonitor.record(
                detectionTimeMilliseconds: detectionMeasurement.elapsedMilliseconds,
                segmentationTimeMilliseconds: segmentationMeasurement.elapsedMilliseconds,
                parkingRuleTimeMilliseconds: parkingRuleMeasurement.elapsedMilliseconds,
                memoryUsageMegabytes: memoryUsage
            )
            state = .completed
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
