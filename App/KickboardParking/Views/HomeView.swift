import SwiftUI

struct HomeView: View {
    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "scooter")
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(.green)

                Text("킥보드 주차 판정")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)

                Text("반납 전 사진을 촬영해 주차 가능 여부를 확인합니다.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            NavigationLink {
                CameraView()
            } label: {
                Label("킥보드 반납", systemImage: "camera.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)

            Spacer()
        }
        .padding(24)
        .background(Color(.systemGroupedBackground))
        .navigationBarBackButtonHidden(true)
    }
}

#Preview {
    NavigationStack {
        HomeView()
    }
}
