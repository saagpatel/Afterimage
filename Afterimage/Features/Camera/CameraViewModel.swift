import AVFoundation
import UIKit
import Observation

@MainActor @Observable
final class CameraViewModel {
    enum Permission {
        case notDetermined, granted, denied
    }

    enum CaptureState {
        case idle, previewing, capturing, captured(UIImage)
    }

    private(set) var permission: Permission = .notDetermined
    private(set) var state: CaptureState = .idle

    let captureSession = AVCaptureSession()
    private var photoOutput = AVCapturePhotoOutput()
    private let coordinator = CameraCoordinator()

    // MARK: - Permission

    func checkPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        permission = mapAuthorizationStatus(status)
    }

    func requestPermission() async {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        permission = granted ? .granted : .denied
    }

    // MARK: - Session Lifecycle

    func startSession() async {
        guard case .granted = permission else { return }

        await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let session = await self.captureSession
            let output = await self.photoOutput

            session.beginConfiguration()
            defer { session.commitConfiguration() }

            // Preset
            if session.canSetSessionPreset(.photo) {
                session.sessionPreset = .photo
            }

            // Input
            guard let device = AVCaptureDevice.default(
                .builtInWideAngleCamera,
                for: .video,
                position: .back
            ) else {
                return
            }

            guard let input = try? AVCaptureDeviceInput(device: device) else {
                return
            }

            guard session.canAddInput(input) else { return }
            session.addInput(input)

            // Output
            guard session.canAddOutput(output) else { return }
            session.addOutput(output)

            session.startRunning()

            await MainActor.run {
                self.state = .previewing
            }
        }.value
    }

    func stopSession() {
        Task.detached(priority: .utility) { [captureSession] in
            captureSession.stopRunning()
        }
    }

    // MARK: - Capture

    func capturePhoto() async throws -> UIImage {
        state = .capturing

        let settings = AVCapturePhotoSettings()
        let image = try await coordinator.capturePhoto(from: photoOutput, settings: settings)

        state = .captured(image)
        return image
    }

    // MARK: - Helpers

    private func mapAuthorizationStatus(_ status: AVAuthorizationStatus) -> Permission {
        switch status {
        case .authorized: .granted
        case .denied, .restricted: .denied
        case .notDetermined: .notDetermined
        @unknown default: .notDetermined
        }
    }
}
