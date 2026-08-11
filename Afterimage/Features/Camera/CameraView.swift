import CoreLocation
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
    var onGalleryPicked: ((UIImage, CLLocation?) -> Void)?
    var onBrowseCities: (() -> Void)?

    @State private var viewModel = CameraViewModel()
    @State private var showingGalleryPicker = false
    @State private var errorMessage: String?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Theme.plate.ignoresSafeArea()

            switch viewModel.permission {
            case .denied:
                permissionContainer(deniedView)

            case .notDetermined:
                permissionContainer(notDeterminedView)

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
        .sheet(isPresented: $showingGalleryPicker) {
            GalleryPickerView(
                onPicked: { image, location in
                    showingGalleryPicker = false
                    onGalleryPicked?(image, location)
                },
                onCancelled: {
                    showingGalleryPicker = false
                },
                onError: { message in
                    showingGalleryPicker = false
                    errorMessage = message
                }
            )
            .ignoresSafeArea()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                viewModel.checkPermission()
                if case .granted = viewModel.permission {
                    Task { await viewModel.startSession() }
                }
            case .background, .inactive:
                viewModel.stopSession()
            @unknown default:
                break
            }
        }
        .alert(
            "Afterimage needs your attention",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Permission States

    private func permissionContainer<Content: View>(_ content: Content) -> some View {
        VStack(spacing: 24) {
            Spacer(minLength: 24)
            content
            alternativeActions
            Spacer(minLength: 24)
        }
        .padding(.horizontal, 24)
    }

    private var deniedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.boneMuted)
            Text("Camera Access Is Off")
                .font(Theme.serifTitle)
                .foregroundStyle(Theme.bone)
            Text("Enable Camera in Settings to take a new photo, or continue with Photos or city browse below.")
                .font(.subheadline)
                .foregroundStyle(Theme.boneMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
            SlabButton(title: "Open Settings") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            .frame(maxWidth: 260)
        }
        .padding(32)
    }

    private var notDeterminedView: some View {
        // A Button (not a bare tap gesture) so VoiceOver can activate it.
        Button {
            Task {
                await viewModel.requestPermission()
                if case .granted = viewModel.permission {
                    await viewModel.startSession()
                }
            }
        } label: {
            VStack(spacing: 20) {
                Image(systemName: "camera")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.bone)
                Text("Tap to Enable Camera")
                    .font(Theme.serifTitle)
                    .foregroundStyle(Theme.bone)
                Text("Match today’s view with a historical photo. Camera access is optional—you can also choose a photo or browse a covered city.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.boneMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Live Preview

    private var livePreviewView: some View {
        ZStack {
            CameraPreview(session: viewModel.captureSession)
                .ignoresSafeArea()

            if case .unavailable(let message) = viewModel.state {
                cameraStatusOverlay(message)
            } else if case .failed(let message) = viewModel.state {
                cameraStatusOverlay(message)
            }

            // Captured thumbnail (top-right)
            if case .captured(let image) = viewModel.state {
                VStack {
                    HStack {
                        Spacer()
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                            .overlay(
                                RoundedRectangle(cornerRadius: 2)
                                    .stroke(Theme.bone, lineWidth: 2)
                            )
                            .padding(.top, 60)
                            .padding(.trailing, 16)
                    }
                    Spacer()
                }
            }

            // Bottom bar: gallery button (left), capture button (center)
            VStack {
                Spacer()
                HStack {
                    galleryButton
                        .padding(.leading, 40)
                    Spacer()
                    captureButton
                    Spacer()
                    browseCitiesButton
                        .padding(.trailing, 40)
                }
                .padding(.bottom, 40)
            }
        }
    }

    private var browseCitiesButton: some View {
        Button {
            onBrowseCities?()
        } label: {
            Image(systemName: "map")
                .font(.system(size: 22))
                .foregroundStyle(Theme.bone)
                .frame(width: 50, height: 50)
                .background(Theme.plate.opacity(0.5), in: Circle())
        }
        .accessibilityLabel("Browse covered cities")
    }

    private var galleryButton: some View {
        Button {
            showingGalleryPicker = true
        } label: {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 22))
                .foregroundStyle(Theme.bone)
                .frame(width: 50, height: 50)
                .background(Theme.plate.opacity(0.5), in: Circle())
        }
        .accessibilityLabel("Choose a photo")
    }

    private var captureButton: some View {
        Button {
            Task {
                do {
                    let image = try await viewModel.capturePhoto()
                    onCapture(image)
                } catch {
                    errorMessage = "The photo could not be captured. Try again or choose one from Photos."
                }
            }
        } label: {
            Circle()
                .fill(Theme.bone)
                .frame(width: 72, height: 72)
                .overlay(
                    Circle()
                        .stroke(Theme.bone.opacity(0.6), lineWidth: 3)
                        .frame(width: 82, height: 82)
                )
        }
        .disabled(!viewModel.canCapture)
        .accessibilityLabel("Take photo")
    }

    private var alternativeActions: some View {
        VStack(spacing: 12) {
            SlabButton(title: "Choose a Photo") {
                showingGalleryPicker = true
            }

            GhostButton(title: "Browse Covered Cities") {
                onBrowseCities?()
            }
        }
        .frame(maxWidth: 300)
    }

    private func cameraStatusOverlay(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.fill")
                .font(.system(size: 32))
                .foregroundStyle(Theme.boneMuted)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.bone)
                .multilineTextAlignment(.center)
            alternativeActions
        }
        .padding(24)
        .background(Theme.plateRaised.opacity(0.92), in: RoundedRectangle(cornerRadius: 4))
        .padding()
    }
}
