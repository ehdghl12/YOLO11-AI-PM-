import Foundation
import SwiftUI
import UIKit

struct DetectionResultView: View {
    let image: UIImage

    @StateObject private var viewModel = DetectionViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .overlay {
                        ZStack {
                            CrosswalkMaskOverlay(
                                imageSize: image.pixelSize,
                                regions: viewModel.crosswalkRegions
                            )

                            BoundingBoxOverlay(
                                imageSize: image.pixelSize,
                                detections: viewModel.detections,
                                isDebugMode: viewModel.isDebugMode
                            )
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .background(Color.black)

                resultContent
                    .padding(.horizontal, 18)
                    .padding(.bottom, 24)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("판정 결과")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.runDetectionIfNeeded(on: image)
        }
        .onChange(of: viewModel.isDebugMode) { _, _ in
            Task {
                await viewModel.runDetection(on: image)
            }
        }
    }

    @ViewBuilder
    private var resultContent: some View {
        VStack(spacing: 16) {
            debugModeToggle

            switch viewModel.state {
            case .idle, .running:
                VStack(spacing: 12) {
                    ProgressView()
                    Text("사진을 분석하는 중입니다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)

            case .failed(let message):
                ParkingResultCard(
                    title: "분석 실패",
                    message: message,
                    violations: []
                )
                DetectionSummarySection(detections: viewModel.detections)

            case .completed:
                if let assessment = viewModel.assessment {
                    ParkingResultCard(
                        title: assessment.message,
                        message: resultCardMessage(for: assessment),
                        violations: assessment.violations
                    )
                }

                if let performanceStatistics = viewModel.performanceStatistics {
                    PerformanceDashboardCard(statistics: performanceStatistics)
                }

                DetectionSummarySection(detections: viewModel.detections)
                DetectionList(detections: viewModel.detections)
            }

            if viewModel.isDebugMode {
                DetectionDebugPanel(
                    detections: viewModel.detections,
                    crosswalkRegions: viewModel.crosswalkRegions,
                    crosswalkDebugInfo: viewModel.assessment?.crosswalkDebugInfo
                )
            }
        }
    }

    private var debugModeToggle: some View {
        Toggle(isOn: $viewModel.isDebugMode) {
            Label("Debug Mode", systemImage: "terminal")
                .font(.headline)
        }
        .toggleStyle(.switch)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }

    private func resultCardMessage(for assessment: ParkingAssessment) -> String {
        switch assessment.status {
        case .allowed:
            return "금지 객체와의 거리가 기준보다 멉니다."
        case .prohibited:
            return "사유"
        case .kickboardMissing:
            return ""
        }
    }
}

#Preview {
    NavigationStack {
        DetectionResultView(image: UIImage(systemName: "photo") ?? UIImage())
    }
}

private struct DetectionClassCount: Identifiable {
    let detectedClass: DetectionClass
    let count: Int

    var id: DetectionClass {
        detectedClass
    }
}

private struct DetectionSummarySection: View {
    let detections: [DetectionResult]

    private var visibleDetections: [DetectionResult] {
        detections.filter { !$0.detectedClass.isIgnoredByAppPolicy }
    }

    private var classCounts: [DetectionClassCount] {
        DetectionClass.appVisibleClasses.map { detectedClass in
            DetectionClassCount(
                detectedClass: detectedClass,
                count: visibleDetections.filter { $0.detectedClass == detectedClass }.count
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Detection Summary")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(classCounts) { item in
                    HStack {
                        Text(item.detectedClass.rawValue)
                            .font(.subheadline.monospaced())
                        Spacer()
                        Text("\(item.count) \(item.count == 1 ? "detection" : "detections")")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct DetectionDebugPanel: View {
    let detections: [DetectionResult]
    let crosswalkRegions: [CrosswalkRegion]
    let crosswalkDebugInfo: CrosswalkDebugInfo?

    private var visibleDetections: [DetectionResult] {
        detections.filter { !$0.detectedClass.isIgnoredByAppPolicy }
    }

    private var classCounts: [DetectionClassCount] {
        DetectionClass.appVisibleClasses.map { detectedClass in
            DetectionClassCount(
                detectedClass: detectedClass,
                count: visibleDetections.filter { $0.detectedClass == detectedClass }.count
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Debug Detections")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                Text("Class Counts")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(classCounts) { item in
                    HStack {
                        Text(item.detectedClass.rawValue)
                            .font(.caption.monospaced())
                        Spacer()
                        Text("\(item.count)")
                            .font(.caption.monospacedDigit().weight(.semibold))
                    }
                }
            }

            Divider()

            CrosswalkDebugSection(
                regions: crosswalkRegions,
                debugInfo: crosswalkDebugInfo
            )

            Divider()

            if visibleDetections.isEmpty {
                Text("검출된 객체가 없습니다.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(visibleDetections) { detection in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(detection.className)
                                .font(.caption.weight(.semibold).monospaced())

                            Text("confidence: \(detection.confidence, specifier: "%.6f")")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)

                            Text(boundingBoxText(for: detection.boundingBox))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }

    private func boundingBoxText(for box: BoundingBoxModel) -> String {
        String(
            format: "box: x=%.1f y=%.1f width=%.1f height=%.1f",
            Double(box.x),
            Double(box.y),
            Double(box.width),
            Double(box.height)
        )
    }
}

private struct CrosswalkDebugSection: View {
    let regions: [CrosswalkRegion]
    let debugInfo: CrosswalkDebugInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Crosswalk")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Text("Crosswalk Count: \(regions.count)")
                .font(.caption.monospacedDigit())

            Text("Polygon Points: \(polygonPointText)")
                .font(.caption.monospacedDigit())

            Text("Kickboard Center: \(kickboardCenterText)")
                .font(.caption.monospacedDigit())

            Text("Inside Crosswalk: \(insideCrosswalkText)")
                .font(.caption.monospacedDigit().weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var polygonPointText: String {
        let counts = debugInfo?.polygonPointCounts ?? regions.map(\.polygon.count)
        guard !counts.isEmpty else {
            return "0"
        }

        return counts.map(String.init).joined(separator: ", ")
    }

    private var kickboardCenterText: String {
        guard let center = debugInfo?.kickboardCenter else {
            return "N/A"
        }

        return String(format: "(%.1f, %.1f)", Double(center.x), Double(center.y))
    }

    private var insideCrosswalkText: String {
        guard let debugInfo else {
            return "N/A"
        }

        return debugInfo.isInsideCrosswalk ? "TRUE" : "FALSE"
    }
}
