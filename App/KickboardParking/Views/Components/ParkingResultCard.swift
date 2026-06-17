import SwiftUI

struct ParkingResultCard: View {
    let title: String
    let message: String
    let violations: [ParkingViolation]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.bold())
                .frame(maxWidth: .infinity, alignment: .leading)

            if violations.isEmpty {
                if !message.isEmpty {
                    Text(message)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(message)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(violations) { violation in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(.red)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(violation.reasonText)
                                    .font(.body)

                                if let normalizedDistance = violation.normalizedDistance,
                                   let threshold = violation.threshold {
                                    Text("정규화 거리 \(normalizedDistance, specifier: "%.2f") / 기준 \(threshold, specifier: "%.2f")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}
