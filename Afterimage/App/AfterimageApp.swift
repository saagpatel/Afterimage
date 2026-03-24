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

    var body: some View {
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
