import SwiftUI
import AVFoundation

// MARK: - CameraPreview

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let layer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
            layer.frame = uiView.bounds
        }
    }
}

// MARK: - CameraView

struct CameraView: View {
    var onCapture: (UIImage) -> Void

    @State private var viewModel = CameraViewModel()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch viewModel.permission {
            case .denied:
                deniedView

            case .notDetermined:
                notDeterminedView

            case .granted:
                livePreviewView
            }
        }
        .onAppear {
            viewModel.checkPermission()
            if case .granted = viewModel.permission {
                Task { await viewModel.startSession() }
            }
        }
        .onDisappear {
            viewModel.stopSession()
        }
    }

    // MARK: - Permission States

    private var deniedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 48))
                .foregroundStyle(.white)
            Text("Camera Access Required")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
            Text("Enable camera access in Settings to use Afterimage.")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
            Button("Open Settings") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(.black)
        }
        .padding(32)
    }

    private var notDeterminedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera")
                .font(.system(size: 48))
                .foregroundStyle(.white)
            Text("Tap to Enable Camera")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            Task {
                await viewModel.requestPermission()
                if case .granted = viewModel.permission {
                    await viewModel.startSession()
                }
            }
        }
    }

    // MARK: - Live Preview

    private var livePreviewView: some View {
        ZStack {
            CameraPreview(session: viewModel.captureSession)
                .ignoresSafeArea()

            // Captured thumbnail (top-right)
            if case .captured(let image) = viewModel.state {
                VStack {
                    HStack {
                        Spacer()
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(.white, lineWidth: 2)
                            )
                            .padding(.top, 60)
                            .padding(.trailing, 16)
                    }
                    Spacer()
                }
            }

            // Capture button (bottom center)
            VStack {
                Spacer()
                captureButton
                    .padding(.bottom, 40)
            }
        }
    }

    private var captureButton: some View {
        Button {
            Task {
                guard let image = try? await viewModel.capturePhoto() else { return }
                onCapture(image)
            }
        } label: {
            Circle()
                .fill(.white)
                .frame(width: 72, height: 72)
                .overlay(
                    Circle()
                        .stroke(.white.opacity(0.6), lineWidth: 3)
                        .frame(width: 82, height: 82)
                )
        }
        .disabled({
            if case .capturing = viewModel.state { return true }
            return false
        }())
    }
}
