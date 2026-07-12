import AVFoundation
import UIKit

/// Owns every mutable AVFoundation session resource on one serial queue.
///
/// AVFoundation predates Swift concurrency and its session types are not `Sendable`.
/// This wrapper is safe to send because callers cannot access the photo output or
/// mutate the session, and all lifecycle and capture operations are serialized.
final class CameraSessionController: NSObject, @unchecked Sendable {
    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "com.afterimage.camera-session")
    private let photoOutput = AVCapturePhotoOutput()
    private var configured = false
    private var captureContinuation: CheckedContinuation<UIImage, any Error>?

    func start() async throws {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [self] in
                do {
                    try configureIfNeeded()
                    if !session.isRunning {
                        session.startRunning()
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() {
        sessionQueue.async { [self] in
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    func capturePhoto() async throws -> UIImage {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [self] in
                guard captureContinuation == nil else {
                    continuation.resume(throwing: CameraError.captureInProgress)
                    return
                }
                captureContinuation = continuation
                photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
            }
        }
    }

    private func configureIfNeeded() throws {
        guard !configured else { return }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        if session.canSetSessionPreset(.photo) {
            session.sessionPreset = .photo
        }

        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
        ) else {
            throw CameraError.noCameraDevice
        }

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input), session.canAddOutput(photoOutput) else {
            throw CameraError.sessionConfigurationFailed
        }

        session.addInput(input)
        session.addOutput(photoOutput)
        configured = true
    }

    private func finishCapture(with result: Result<UIImage, any Error>) {
        sessionQueue.async { [self] in
            guard let continuation = captureContinuation else { return }
            captureContinuation = nil
            continuation.resume(with: result)
        }
    }
}

extension CameraSessionController: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: (any Error)?
    ) {
        if let error {
            finishCapture(with: .failure(error))
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            finishCapture(with: .failure(CameraError.noImageData))
            return
        }
        guard let image = UIImage(data: data) else {
            finishCapture(with: .failure(CameraError.invalidImageData))
            return
        }
        finishCapture(with: .success(image))
    }
}

enum CameraError: LocalizedError {
    case noImageData
    case invalidImageData
    case noCameraDevice
    case sessionConfigurationFailed
    case captureDenied
    case captureInProgress

    var errorDescription: String? {
        switch self {
        case .noImageData: "No image data returned from capture."
        case .invalidImageData: "Captured data could not be converted to an image."
        case .noCameraDevice: "No rear camera device found."
        case .sessionConfigurationFailed: "Failed to configure the capture session."
        case .captureDenied: "Camera access has been denied."
        case .captureInProgress: "A photo capture is already in progress."
        }
    }
}
