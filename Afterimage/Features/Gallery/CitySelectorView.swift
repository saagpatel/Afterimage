import CoreLocation
import SwiftUI

// MARK: - CityInfo

struct CityInfo: Identifiable {
    let id: String
    let name: String
    let coordinate: CLLocationCoordinate2D
    let photoCount: Int?

    static let allCities: [CityInfo] = [
        CityInfo(id: "nyc", name: "New York City",
                 coordinate: .init(latitude: 40.7128, longitude: -74.0060), photoCount: nil),
        CityInfo(id: "sf", name: "San Francisco",
                 coordinate: .init(latitude: 37.7749, longitude: -122.4194), photoCount: nil),
        CityInfo(id: "chicago", name: "Chicago",
                 coordinate: .init(latitude: 41.8781, longitude: -87.6298), photoCount: nil),
        CityInfo(id: "dc", name: "Washington, D.C.",
                 coordinate: .init(latitude: 38.9072, longitude: -77.0369), photoCount: nil),
        CityInfo(id: "new_orleans", name: "New Orleans",
                 coordinate: .init(latitude: 29.9511, longitude: -90.0715), photoCount: nil),
        CityInfo(id: "boston", name: "Boston",
                 coordinate: .init(latitude: 42.3601, longitude: -71.0589), photoCount: nil),
    ]
}

// MARK: - CitySelectorView

struct CitySelectorView: View {
    let onCitySelected: (CityInfo) -> Void
    let onDismissed: () -> Void

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        EyebrowText("The Collection", color: Theme.boneMuted)
                        Text("Choose a City")
                            .font(.system(.title, design: .serif).weight(.bold))
                            .foregroundStyle(Theme.bone)
                    }
                    .padding(.top, 4)

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(CityInfo.allCities) { city in
                            CityCard(city: city) {
                                onCitySelected(city)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Theme.plate)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismissed() }
                        .tint(Theme.bone)
                }
            }
        }
    }
}

// MARK: - CityCard

private struct CityCard: View {
    let city: CityInfo
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                Text(city.name)
                    .font(.system(.headline, design: .serif))
                    .foregroundStyle(Theme.bone)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if let count = city.photoCount {
                    Text("\(count.formatted()) plates")
                        .font(Theme.metaFont)
                        .foregroundStyle(Theme.boneMuted)
                } else {
                    Text("Historical photos")
                        .font(Theme.metaFont)
                        .foregroundStyle(Theme.boneMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Theme.plateRaised, in: RoundedRectangle(cornerRadius: 2))
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Theme.boneFaint.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
