import SwiftUI

struct DetectionList: View {
    let detections: [DetectionResult]

    private var visibleDetections: [DetectionResult] {
        detections.filter { !$0.detectedClass.isIgnoredByAppPolicy }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("검출 객체")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            if visibleDetections.isEmpty {
                Text("표시할 검출 결과가 없습니다.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(spacing: 8) {
                    ForEach(visibleDetections) { detection in
                        DetectionRow(detection: detection)
                    }
                }
            }
        }
    }
}

struct DetectionRow: View {
    let detection: DetectionResult

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(DetectionPalette.color(for: detection.detectedClass))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(detection.detectedClass.displayName)
                    .font(.body.weight(.semibold))

                Text(detection.className)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(detection.confidence, format: .percent.precision(.fractionLength(1)))
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}
