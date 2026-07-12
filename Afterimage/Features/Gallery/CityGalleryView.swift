import Kingfisher
import SwiftUI

struct CityGalleryView: View {
    let city: CityInfo
    let loadPhotos: () async throws -> [HistoricalPhoto]
    let onDismissed: () -> Void

    @State private var photos: [HistoricalPhoto] = []
    @State private var selectedPhoto: HistoricalPhoto?
    @State private var loadError: String?
    @State private var isLoading = true

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 12)]

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading historical photos…")
                } else if let loadError {
                    ContentUnavailableView(
                        "Photos Unavailable",
                        systemImage: "photo.badge.exclamationmark",
                        description: Text(loadError)
                    )
                } else if photos.isEmpty {
                    ContentUnavailableView(
                        "No Photos Available",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("The bundled index does not contain photos for this city.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(photos) { photo in
                                Button { selectedPhoto = photo } label: {
                                    CityPhotoCard(photo: photo)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(photo.title)
                                .accessibilityHint("Shows photo details")
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle(city.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cities", systemImage: "chevron.left", action: onDismissed)
                }
            }
        }
        .task { await load() }
        .sheet(item: $selectedPhoto) { photo in
            CityPhotoDetail(photo: photo)
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            photos = try await loadPhotos()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}

private struct CityPhotoCard: View {
    let photo: HistoricalPhoto

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            KFImage(URL(string: photo.thumbnailURL))
                .placeholder {
                    ZStack {
                        Color.secondary.opacity(0.12)
                        ProgressView()
                    }
                }
                .resizable()
                .cancelOnDisappear(true)
                .scaledToFill()
                .frame(height: 130)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10))

            Text(photo.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            Text(photo.dateText ?? "Date unknown")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CityPhotoDetail: View {
    let photo: HistoricalPhoto
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    KFImage(URL(string: photo.fullResURL ?? photo.thumbnailURL))
                        .placeholder { ProgressView().frame(maxWidth: .infinity, minHeight: 240) }
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(photo.title)

                    Text(photo.title).font(.title2.weight(.semibold))
                    if let date = photo.dateText {
                        Text(date).font(.headline).foregroundStyle(.secondary)
                    }
                    if let description = photo.description, !description.isEmpty {
                        Text(description)
                    }
                    Text(photo.attribution)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("Historical Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
