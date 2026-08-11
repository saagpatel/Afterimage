import SwiftUI

struct ComparisonView: View {
    let userPhoto: UIImage
    let match: MatchCandidate
    let onDismiss: () -> Void

    /// 0 = all historical, 1 = all today. Owned here so the share
    /// export freezes the plate exactly as the viewer left it.
    @State private var revealFraction: CGFloat = 0.5

    var body: some View {
        VStack(spacing: 0) {
            header

            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 20) {
                        mountedPlate

                        MuseumLabelCard(match: match)
                    }
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .center)
                }
            }
        }
        .background(Theme.plate.ignoresSafeArea())
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button(action: onDismiss) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                    EyebrowText("Back", color: Theme.bone)
                }
                .foregroundStyle(Theme.bone)
                .frame(minHeight: 44)
            }
            .accessibilityLabel("Back")
            .accessibilityIdentifier("Back")

            Spacer()

            if let thumbnail = match.thumbnail {
                ShareLink(
                    item: PlateExport(
                        userPhoto: userPhoto,
                        historicalPhoto: thumbnail,
                        match: match,
                        revealFraction: revealFraction
                    ),
                    preview: SharePreview(match.photo.title, image: Image(uiImage: thumbnail))
                ) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 13, weight: .semibold))
                        EyebrowText("Share", color: Theme.bone)
                    }
                    .foregroundStyle(Theme.bone)
                    .frame(minHeight: 44)
                }
                .accessibilityLabel("Share")
                .accessibilityIdentifier("Share")
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - The mounted plate

    private var mountedPlate: some View {
        Group {
            if let thumbnail = match.thumbnail {
                SliderOverlayView(
                    userPhoto: userPhoto,
                    historicalPhoto: thumbnail,
                    eraLabel: match.eraLabel,
                    revealFraction: $revealFraction
                )
                .aspectRatio(4.0 / 3.0, contentMode: .fit)
            } else {
                Theme.plateRaised
                    .aspectRatio(4.0 / 3.0, contentMode: .fit)
                    .overlay {
                        ProgressView()
                            .tint(Theme.boneMuted)
                    }
            }
        }
        .plateFrame()
    }
}
