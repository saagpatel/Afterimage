import CoreLocation
import PhotosUI
import SwiftUI
import UIKit

/// PHPickerViewController wrapper. On selection, extracts UIImage + GPS from the PHAsset.
/// `onPicked` is called with the image and an optional location.
/// If the asset has no location data, `CLLocation` will be nil and the caller should
/// present a manual location picker.
struct GalleryPickerView: UIViewControllerRepresentable {
    var onPicked: (UIImage, CLLocation?) -> Void
    var onCancelled: () -> Void
    var onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked, onCancelled: onCancelled, onError: onError)
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = 1
        // Request location data without requesting full photo library access
        config.preferredAssetRepresentationMode = .current

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let onPicked: (UIImage, CLLocation?) -> Void
        private let onCancelled: () -> Void
        private let onError: (String) -> Void

        init(
            onPicked: @escaping (UIImage, CLLocation?) -> Void,
            onCancelled: @escaping () -> Void,
            onError: @escaping (String) -> Void
        ) {
            self.onPicked = onPicked
            self.onCancelled = onCancelled
            self.onError = onError
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let result = results.first else {
                onCancelled()
                return
            }

            // Load image
            result.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] object, error in
                guard let self, let image = object as? UIImage else {
                    DispatchQueue.main.async {
                        self?.onError("That photo could not be loaded. Choose a different image and try again.")
                    }
                    return
                }

                // Try to extract GPS location from the PHAsset
                guard let assetIdentifier = result.assetIdentifier else {
                    DispatchQueue.main.async { self.onPicked(image, nil) }
                    return
                }

                let fetchResult = PHAsset.fetchAssets(
                    withLocalIdentifiers: [assetIdentifier],
                    options: nil
                )
                let location = fetchResult.firstObject?.location
                DispatchQueue.main.async { self.onPicked(image, location) }
            }
        }
    }
}
