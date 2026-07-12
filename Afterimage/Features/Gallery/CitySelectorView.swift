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
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(CityInfo.allCities) { city in
                        CityCard(city: city) {
                            onCitySelected(city)
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle("Choose a City")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismissed() }
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
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if let count = city.photoCount {
                    Text("\(count.formatted()) photos")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Historical photos")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.secondary.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
