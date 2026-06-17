import Foundation
import SwiftUI

struct PerformanceDashboardCard: View {
    let statistics: PerformanceStatistics

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Performance Dashboard")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            metricGroup(
                title: "Current",
                rows: [
                    ("Detection", milliseconds(statistics.current.detectionTimeMilliseconds)),
                    ("Segmentation", milliseconds(statistics.current.segmentationTimeMilliseconds)),
                    ("Parking Rule", milliseconds(statistics.current.parkingRuleTimeMilliseconds)),
                    ("Total", milliseconds(statistics.current.totalProcessingTimeMilliseconds)),
                    ("Current Memory", megabytes(statistics.current.memoryUsageMegabytes))
                ]
            )

            Divider()

            metricGroup(
                title: "Last 50 Statistics",
                rows: [
                    ("Average Detection", milliseconds(statistics.averageDetectionTimeMilliseconds)),
                    ("Peak Detection", milliseconds(statistics.maximumDetectionTimeMilliseconds)),
                    ("Average Segmentation", milliseconds(statistics.averageSegmentationTimeMilliseconds)),
                    ("Peak Segmentation", milliseconds(statistics.maximumSegmentationTimeMilliseconds)),
                    ("Average Total", milliseconds(statistics.averageTotalTimeMilliseconds)),
                    ("Peak Total", milliseconds(statistics.maximumTotalTimeMilliseconds)),
                    ("Average Memory", megabytes(statistics.averageMemoryUsageMegabytes)),
                    ("Peak Memory", megabytes(statistics.maximumMemoryUsageMegabytes))
                ]
            )
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }

    private func metricGroup(title: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach(rows, id: \.0) { title, value in
                    HStack(alignment: .firstTextBaseline) {
                        Text(title)
                            .font(.subheadline)
                        Spacer()
                        Text(value)
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                    }
                }
            }
        }
    }

    private func milliseconds(_ value: Double) -> String {
        "\(String(format: "%.0f", value)) ms"
    }

    private func megabytes(_ value: Double) -> String {
        "\(String(format: "%.0f", value)) MB"
    }
}
