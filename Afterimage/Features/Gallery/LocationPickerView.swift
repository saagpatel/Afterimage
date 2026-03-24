import CoreLocation
import MapKit
import SwiftUI

/// Map view where the user taps to place a pin and confirm a location.
/// Used when a gallery photo has no GPS data.
struct LocationPickerView: View {
    let photo: UIImage
    var onConfirmed: (CLLocation) -> Void
    var onCancelled: () -> Void

    @State private var cameraPosition = MapCameraPosition.region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
    )
    @State private var pin: CLLocationCoordinate2D?

    var body: some View {
        NavigationStack {
            ZStack {
                MapReader { proxy in
                    Map(position: $cameraPosition) {
                        if let pin {
                            Marker("Selected location", coordinate: pin)
                                .tint(.red)
                        }
                    }
                    .ignoresSafeArea(edges: .bottom)
                    .onTapGesture { screenPoint in
                        if let coordinate = proxy.convert(screenPoint, from: .local) {
                            pin = coordinate
                            cameraPosition = .region(MKCoordinateRegion(
                                center: coordinate,
                                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                            ))
                        }
                    }
                }

                if pin == nil {
                    VStack {
                        tapHintBanner
                        Spacer()
                    }
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Where was this taken?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancelled() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Match") {
                        guard let coordinate = pin else { return }
                        onConfirmed(CLLocation(
                            latitude: coordinate.latitude,
                            longitude: coordinate.longitude
                        ))
                    }
                    .disabled(pin == nil)
                }
            }
        }
    }

    private var tapHintBanner: some View {
        Text("Tap the map to pin the location")
            .font(.subheadline)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
    }
}
