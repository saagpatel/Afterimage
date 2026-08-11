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
        // The whole app lives in the plate archive's dark; system chrome
        // (nav bars, sheets, alerts) should match.
        .preferredColorScheme(.dark)
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
                .plateFrame()
            Text("Your photo is still here")
                .font(Theme.serifTitle)
                .foregroundStyle(Theme.bone)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.boneMuted)
                .multilineTextAlignment(.center)
            SlabButton(title: "Choose Location Manually", action: onChooseLocation)
            GhostButton(title: "Browse Covered Cities", action: onBrowseCities)
            QuietButton(title: "Start Over", action: onStartOver)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.plate.ignoresSafeArea())
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
                .plateFrame()

            switch appState.matchingService.state {
            case .searching(let stage):
                ProgressView()
                    .controlSize(.large)
                    .tint(Theme.boneMuted)
                EyebrowText(stage, color: Theme.boneMuted)
                    .multilineTextAlignment(.center)

            case .noResults:
                noResultsView

            case .error(let message):
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.albumen)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Theme.boneMuted)
                    .multilineTextAlignment(.center)
                GhostButton(title: "Back to Camera") {
                    appState.currentScreen = .camera
                }

            default:
                ProgressView()
                    .tint(Theme.boneMuted)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.plate.ignoresSafeArea())
    }

    private var noResultsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(Theme.boneMuted)
            Text("No historical photos found here")
                .font(Theme.serifTitle)
                .foregroundStyle(Theme.bone)
            if let cityDescription = appState.nearestCityDescription() {
                Text("The nearest covered city is \(cityDescription).")
                    .font(.subheadline)
                    .foregroundStyle(Theme.boneMuted)
                    .multilineTextAlignment(.center)
            }
            GhostButton(title: "Try a Different Location") {
                appState.currentScreen = .camera
            }
            .padding(.top, 4)
        }
    }
}
