import SwiftUI

struct CameraView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = CameraViewModel()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch viewModel.authorizationState {
            case .authorized:
                CameraPreview(session: viewModel.session)
                    .ignoresSafeArea()
            case .notDetermined:
                ProgressView()
                    .tint(.white)
            case .denied:
                permissionDeniedView
            }

            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.headline)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .accessibilityLabel("뒤로가기")

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                Spacer()

                Button {
                    viewModel.capturePhoto()
                } label: {
                    ZStack {
                        Circle()
                            .stroke(.white, lineWidth: 5)
                            .frame(width: 76, height: 76)

                        Circle()
                            .fill(.white)
                            .frame(width: 60, height: 60)
                    }
                }
                .disabled(viewModel.authorizationState != .authorized || !viewModel.isSessionRunning)
                .accessibilityLabel("사진 촬영")
                .padding(.bottom, 34)
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            viewModel.start()
        }
        .onDisappear {
            viewModel.stop()
        }
        .navigationDestination(
            isPresented: Binding(
                get: { viewModel.isShowingDetectionResult },
                set: { viewModel.setDetectionResultPresented($0) }
            )
        ) {
            if let image = viewModel.capturedPhoto?.image {
                DetectionResultView(image: image)
            } else {
                Text("촬영 이미지를 찾을 수 없습니다. 다시 촬영해주세요.")
            }
        }
        .alert(
            "오류",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { _ in viewModel.errorMessage = nil }
            )
        ) {
            Button("확인", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var permissionDeniedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.slash")
                .font(.system(size: 44, weight: .semibold))

            Text("카메라 권한이 필요합니다.")
                .font(.headline)

            Text("설정에서 카메라 접근을 허용한 뒤 다시 시도해주세요.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white)
        .padding(28)
    }
}

#Preview {
    CameraView()
}
