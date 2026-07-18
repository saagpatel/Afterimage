import SwiftUI

@main
struct AfterimageApp: App {
    @State private var appState = AppState()

    init() {
        ThumbnailCacheConfig.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
        }
    }
}

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch appState.currentScreen {
            case .camera:
                CameraView(
                    onCapture: { photo in
                        appState.onPhotoCaptured(photo)
                    },
                    onGalleryPicked: { image, location in
                        if let location {
                            appState.onGalleryPhotoWithLocation(image, location: location)
                        } else {
                            appState.onGalleryPhotoNeedsLocation(image)
                        }
                    },
                    onBrowseCities: {
                        appState.currentScreen = .citySelector
                    }
                )
                .task {
                    do {
                        let count = try await DatabaseManager.shared.photoCount
                        print("DB opened: \(count) historical photos loaded")
                    } catch {
                        print("DB error: \(error)")
                    }
                }

            case .citySelector:
                CitySelectorView(
                    onCitySelected: { city in
                        appState.onCitySelected(city)
                    },
                    onDismissed: {
                        appState.currentScreen = .camera
                    }
                )

            case .galleryLocationPicker(let image):
                LocationPickerView(
                    photo: image,
                    onConfirmed: { location in
                        appState.onGalleryLocationConfirmed(image, location: location)
                    },
                    onCancelled: {
                        appState.currentScreen = .camera
                    }
                )

            case .captureRecovery(let image, let message):
                CaptureRecoveryView(
                    photo: image,
                    message: message,
                    onChooseLocation: {
                        appState.currentScreen = .galleryLocationPicker(image)
                    },
                    onBrowseCities: {
                        appState.currentScreen = .citySelector
                    },
                    onStartOver: {
                        appState.currentScreen = .camera
                    }
                )

            case .matching(let photo):
                MatchingProgressView(photo: photo)
                    .environment(appState)

            case .comparison(let userPhoto, let match):
                ComparisonView(
                    userPhoto: userPhoto,
                    match: match,
                    onDismiss: { appState.currentScreen = .camera }
                )
            }
        }
        .onAppear {
            appState.locationService.refreshAuthorization()
            #if DEBUG
            appState.applyDebugLaunchArgumentsIfNeeded()
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                appState.locationService.refreshAuthorization()
            }
        }
    }
}

struct CaptureRecoveryView: View {
    let photo: UIImage
    let message: String
    let onChooseLocation: () -> Void
    let onBrowseCities: () -> Void
    let onStartOver: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(uiImage: photo)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 280)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Text("Your photo is still here")
                .font(.title2.bold())
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Choose Location Manually", action: onChooseLocation)
                .buttonStyle(.borderedProminent)
            Button("Browse Covered Cities", action: onBrowseCities)
                .buttonStyle(.bordered)
            Button("Start Over", action: onStartOver)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .padding(28)
    }
}

struct MatchingProgressView: View {
    let photo: UIImage
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 20) {
            Image(uiImage: photo)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            switch appState.matchingService.state {
            case .searching(let stage):
                ProgressView()
                    .controlSize(.large)
                Text(stage)
                    .foregroundStyle(.secondary)

            case .noResults:
                noResultsView

            case .error(let message):
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)
                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Back to Camera") {
                    appState.currentScreen = .camera
                }
                .buttonStyle(.bordered)

            default:
                ProgressView()
            }
        }
        .padding(32)
    }

    private var noResultsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No historical photos found here")
                .font(.headline)
            if let cityDescription = appState.nearestCityDescription() {
                Text("The nearest covered city is \(cityDescription).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button("Try a Different Location") {
                appState.currentScreen = .camera
            }
            .buttonStyle(.bordered)
            .padding(.top, 4)
        }
    }
}
