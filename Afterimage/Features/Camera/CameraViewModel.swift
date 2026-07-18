import AVFoundation
import UIKit
import Observation

@MainActor @Observable
final class CameraViewModel {
    enum Permission: Equatable {
        case notDetermined, granted, denied
    }

    enum CaptureState {
        case idle, previewing, capturing, captured(UIImage), unavailable(String), failed(String)
    }

    private(set) var permission: Permission = .notDetermined
    private(set) var state: CaptureState = .idle

    let captureSession = AVCaptureSession()
    private var photoOutput = AVCapturePhotoOutput()
    private let coordinator = CameraCoordinator()
    private var isStartingSession = false

    var canCapture: Bool {
        if case .previewing = state { return true }
        return false
    }

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
        guard !isStartingSession else { return }
        if captureSession.isRunning {
            state = .previewing
            return
        }
        isStartingSession = true
        defer { isStartingSession = false }

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
                await MainActor.run {
                    self.state = .unavailable("No rear camera is available. You can still use a photo or browse a city.")
                }
                return
            }

            guard let input = try? AVCaptureDeviceInput(device: device) else {
                await MainActor.run {
                    self.state = .unavailable("The camera could not be started. You can still use a photo or browse a city.")
                }
                return
            }

            if session.inputs.isEmpty {
                guard session.canAddInput(input) else {
                    await MainActor.run {
                        self.state = .unavailable("The camera is unavailable. You can still use a photo or browse a city.")
                    }
                    return
                }
                session.addInput(input)
            }

            // Output
            if session.outputs.isEmpty {
                guard session.canAddOutput(output) else {
                    await MainActor.run {
                        self.state = .unavailable("Photo capture is unavailable. You can still use a photo or browse a city.")
                    }
                    return
                }
                session.addOutput(output)
            }

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
        guard canCapture else {
            throw NSError(
                domain: "Afterimage.Camera",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Camera is not ready"]
            )
        }
        state = .capturing

        let settings = AVCapturePhotoSettings()
        do {
            let image = try await coordinator.capturePhoto(from: photoOutput, settings: settings)

            state = .captured(image)
            return image
        } catch {
            state = .failed("The photo could not be captured. Try again or choose one from Photos.")
            throw error
        }
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
