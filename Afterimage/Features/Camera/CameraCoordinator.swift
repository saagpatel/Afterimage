import AVFoundation
import UIKit

final class CameraCoordinator: NSObject, AVCapturePhotoCaptureDelegate {
    private var continuation: CheckedContinuation<UIImage, any Error>?

    func capturePhoto(from output: AVCapturePhotoOutput, settings: AVCapturePhotoSettings) async throws -> UIImage {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            output.capturePhoto(with: settings, delegate: self)
        }
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: (any Error)?
    ) {
        if let error {
            continuation?.resume(throwing: error)
            continuation = nil
            return
        }

        guard let data = photo.fileDataRepresentation() else {
            continuation?.resume(throwing: CameraError.noImageData)
            continuation = nil
            return
        }

        guard let image = UIImage(data: data) else {
            continuation?.resume(throwing: CameraError.invalidImageData)
            continuation = nil
            return
        }

        continuation?.resume(returning: image)
        continuation = nil
    }
}

// MARK: - CameraError

enum CameraError: LocalizedError {
    case noImageData
    case invalidImageData
    case noCameraDevice
    case sessionConfigurationFailed
    case captureDenied

    var errorDescription: String? {
        switch self {
        case .noImageData: "No image data returned from capture."
        case .invalidImageData: "Captured data could not be converted to an image."
        case .noCameraDevice: "No rear camera device found."
        case .sessionConfigurationFailed: "Failed to configure the capture session."
        case .captureDenied: "Camera access has been denied."
        }
    }
}
