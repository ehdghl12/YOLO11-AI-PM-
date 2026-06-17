import AVFoundation
import Foundation
import UIKit

enum CameraAuthorizationState: Equatable {
    case notDetermined
    case authorized
    case denied
}

struct CapturedPhoto {
    let image: UIImage
}

final class CameraViewModel: NSObject, ObservableObject {
    @Published private(set) var authorizationState: CameraAuthorizationState = .notDetermined
    @Published private(set) var isSessionRunning = false
    @Published private(set) var capturedPhoto: CapturedPhoto?
    @Published private(set) var isShowingDetectionResult = false
    @Published var errorMessage: String?

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "com.donghoe.kickboard.camera.session")
    private let photoOutput = AVCapturePhotoOutput()
    private var isConfigured = false
    private var photoProcessor: PhotoCaptureProcessor?

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            authorizationState = .authorized
            configureAndStartSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.authorizationState = granted ? .authorized : .denied
                    if granted {
                        self?.configureAndStartSession()
                    }
                }
            }
        default:
            authorizationState = .denied
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else {
                return
            }

            if self.session.isRunning {
                self.session.stopRunning()
            }

            DispatchQueue.main.async {
                self.isSessionRunning = false
            }
        }
    }

    func capturePhoto() {
        sessionQueue.async { [weak self] in
            guard let self else {
                return
            }

            guard self.isConfigured, self.session.isRunning else {
                DispatchQueue.main.async {
                    self.errorMessage = "카메라가 준비되지 않았습니다. 잠시 후 다시 시도해주세요."
                }
                return
            }

            let settings = AVCapturePhotoSettings()
            settings.photoQualityPrioritization = .balanced

            let processor = PhotoCaptureProcessor { [weak self] result in
                DispatchQueue.main.async {
                    guard let self else {
                        return
                    }

                    switch result {
                    case .success(let image):
                        self.capturedPhoto = CapturedPhoto(image: image)
                        self.isShowingDetectionResult = true
                    case .failure:
                        self.errorMessage = "사진 촬영에 실패했습니다. 다시 촬영해주세요."
                    }

                    self.photoProcessor = nil
                }
            }

            self.photoProcessor = processor
            self.photoOutput.capturePhoto(with: settings, delegate: processor)
        }
    }

    func setDetectionResultPresented(_ isPresented: Bool) {
        isShowingDetectionResult = isPresented

        if !isPresented {
            capturedPhoto = nil
        }
    }

    private func configureAndStartSession() {
        sessionQueue.async { [weak self] in
            guard let self else {
                return
            }

            do {
                if !self.isConfigured {
                    try self.configureSession()
                    self.isConfigured = true
                }

                if !self.session.isRunning {
                    self.session.startRunning()
                }

                DispatchQueue.main.async {
                    self.isSessionRunning = true
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "카메라를 실행하지 못했습니다. 권한과 기기 상태를 확인해주세요."
                }
            }
        }
    }

    private func configureSession() throws {
        session.beginConfiguration()
        session.sessionPreset = .photo
        defer {
            session.commitConfiguration()
        }

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw CameraConfigurationError.cameraUnavailable
        }

        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input) else {
            throw CameraConfigurationError.inputUnavailable
        }
        session.addInput(input)

        guard session.canAddOutput(photoOutput) else {
            throw CameraConfigurationError.outputUnavailable
        }
        session.addOutput(photoOutput)
        photoOutput.maxPhotoQualityPrioritization = .balanced
    }
}

private enum CameraConfigurationError: Error {
    case cameraUnavailable
    case inputUnavailable
    case outputUnavailable
}

private final class PhotoCaptureProcessor: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (Result<UIImage, Error>) -> Void

    init(completion: @escaping (Result<UIImage, Error>) -> Void) {
        self.completion = completion
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            completion(.failure(error))
            return
        }

        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data)
        else {
            completion(.failure(CameraConfigurationError.outputUnavailable))
            return
        }

        completion(.success(image.normalizedForAnalysis))
    }
}
