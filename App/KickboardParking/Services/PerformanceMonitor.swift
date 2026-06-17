import Darwin
import Dispatch
import Foundation

struct TimedOperation<Value> {
    let value: Value
    let elapsedMilliseconds: Double
}

struct PerformanceMeasurement: Identifiable, Equatable {
    let id = UUID()
    let detectionTimeMilliseconds: Double
    let segmentationTimeMilliseconds: Double
    let parkingRuleTimeMilliseconds: Double
    let memoryUsageMegabytes: Double
    let timestamp: Date

    var totalProcessingTimeMilliseconds: Double {
        detectionTimeMilliseconds + segmentationTimeMilliseconds + parkingRuleTimeMilliseconds
    }
}

struct PerformanceStatistics: Equatable {
    let current: PerformanceMeasurement
    let averageDetectionTimeMilliseconds: Double
    let maximumDetectionTimeMilliseconds: Double
    let averageSegmentationTimeMilliseconds: Double
    let maximumSegmentationTimeMilliseconds: Double
    let averageTotalTimeMilliseconds: Double
    let maximumTotalTimeMilliseconds: Double
    let averageMemoryUsageMegabytes: Double
    let maximumMemoryUsageMegabytes: Double
}

final class PerformanceMonitor {
    static let shared = PerformanceMonitor()

    private let maxStoredResults = 50
    private var measurements: [PerformanceMeasurement] = []

    private init() {}

    func measure<Value>(
        _ operation: () async throws -> Value
    ) async rethrows -> TimedOperation<Value> {
        let start = DispatchTime.now().uptimeNanoseconds
        let value = try await operation()
        return TimedOperation(
            value: value,
            elapsedMilliseconds: elapsedMilliseconds(since: start)
        )
    }

    func measure<Value>(
        _ operation: () throws -> Value
    ) rethrows -> TimedOperation<Value> {
        let start = DispatchTime.now().uptimeNanoseconds
        let value = try operation()
        return TimedOperation(
            value: value,
            elapsedMilliseconds: elapsedMilliseconds(since: start)
        )
    }

    func currentMemoryUsageMegabytes() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.stride / MemoryLayout<natural_t>.stride
        )

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    $0,
                    &count
                )
            }
        }

        guard result == KERN_SUCCESS else {
            return 0
        }

        return Double(info.resident_size) / 1024.0 / 1024.0
    }

    @discardableResult
    func record(
        detectionTimeMilliseconds: Double,
        segmentationTimeMilliseconds: Double,
        parkingRuleTimeMilliseconds: Double,
        memoryUsageMegabytes: Double
    ) -> PerformanceStatistics {
        let measurement = PerformanceMeasurement(
            detectionTimeMilliseconds: detectionTimeMilliseconds,
            segmentationTimeMilliseconds: segmentationTimeMilliseconds,
            parkingRuleTimeMilliseconds: parkingRuleTimeMilliseconds,
            memoryUsageMegabytes: memoryUsageMegabytes,
            timestamp: Date()
        )

        measurements.append(measurement)
        if measurements.count > maxStoredResults {
            measurements.removeFirst(measurements.count - maxStoredResults)
        }

        log(measurement)
        return statistics(current: measurement)
    }

    private func statistics(current: PerformanceMeasurement) -> PerformanceStatistics {
        PerformanceStatistics(
            current: current,
            averageDetectionTimeMilliseconds: average(\.detectionTimeMilliseconds),
            maximumDetectionTimeMilliseconds: maximum(\.detectionTimeMilliseconds),
            averageSegmentationTimeMilliseconds: average(\.segmentationTimeMilliseconds),
            maximumSegmentationTimeMilliseconds: maximum(\.segmentationTimeMilliseconds),
            averageTotalTimeMilliseconds: average(\.totalProcessingTimeMilliseconds),
            maximumTotalTimeMilliseconds: maximum(\.totalProcessingTimeMilliseconds),
            averageMemoryUsageMegabytes: average(\.memoryUsageMegabytes),
            maximumMemoryUsageMegabytes: maximum(\.memoryUsageMegabytes)
        )
    }

    private func average(_ keyPath: KeyPath<PerformanceMeasurement, Double>) -> Double {
        guard !measurements.isEmpty else {
            return 0
        }

        let total = measurements.reduce(0) { $0 + $1[keyPath: keyPath] }
        return total / Double(measurements.count)
    }

    private func maximum(_ keyPath: KeyPath<PerformanceMeasurement, Double>) -> Double {
        measurements.map { $0[keyPath: keyPath] }.max() ?? 0
    }

    private func elapsedMilliseconds(since start: UInt64) -> Double {
        let end = DispatchTime.now().uptimeNanoseconds
        return Double(end - start) / 1_000_000.0
    }

    private func log(_ measurement: PerformanceMeasurement) {
        print(
            """
            [Performance]
            Detection: \(format(measurement.detectionTimeMilliseconds)) ms
            Segmentation: \(format(measurement.segmentationTimeMilliseconds)) ms
            Parking Rule: \(format(measurement.parkingRuleTimeMilliseconds)) ms
            Total: \(format(measurement.totalProcessingTimeMilliseconds)) ms
            Memory: \(format(measurement.memoryUsageMegabytes)) MB
            """
        )
    }

    private func format(_ value: Double) -> String {
        String(format: "%.0f", value)
    }
}
