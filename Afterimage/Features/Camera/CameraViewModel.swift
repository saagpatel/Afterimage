import AVFoundation
import UIKit
import Observation

@MainActor @Observable
final class CameraViewModel {
    enum Permission {
        case notDetermined, granted, denied
    }

    enum CaptureState {
        case idle, previewing, capturing, captured(UIImage), failed(String)
    }

    private(set) var permission: Permission = .notDetermined
    private(set) var state: CaptureState = .idle

    private let cameraController = CameraSessionController()

    var captureSession: AVCaptureSession { cameraController.session }

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
        do {
            try await cameraController.start()
            state = .previewing
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func stopSession() {
        cameraController.stop()
    }

    // MARK: - Capture

    func capturePhoto() async throws -> UIImage {
        state = .capturing

        do {
            let image = try await cameraController.capturePhoto()
            state = .captured(image)
            return image
        } catch {
            state = .failed(error.localizedDescription)
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
