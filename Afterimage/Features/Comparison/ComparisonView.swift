import SwiftUI

struct ComparisonView: View {
    let userPhoto: UIImage
    let match: MatchCandidate
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 20) {
                        mountedPlate

                        museumLabel
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
                    eraLabel: eraLabel
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

    // MARK: - The museum label

    private var museumLabel: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let city = match.photo.city {
                EyebrowText(city, color: Theme.inkOnBone)
            }

            Text(match.photo.title)
                .font(Theme.serifTitle)
                .foregroundStyle(Theme.plate)
                .fixedSize(horizontal: false, vertical: true)

            if let dateText = match.photo.dateText {
                Text(dateText)
                    .font(Theme.metaFont.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(Theme.albumenDeep)
            }

            Rectangle()
                .fill(Theme.inkOnBone.opacity(0.25))
                .frame(height: 1)
                .padding(.vertical, 4)

            Text(catalogLine)
                .font(Theme.metaFont)
                .textCase(.uppercase)
                .tracking(1.0)
                .foregroundStyle(Theme.inkOnBone)

            HStack(alignment: .bottom) {
                Text(match.photo.attribution)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Theme.inkOnBone)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 12)

                EyebrowText("Afterimage", color: Theme.inkOnBone)
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.bone, in: RoundedRectangle(cornerRadius: 2))
    }

    // MARK: - Catalog copy

    /// Chip text for the historical layer: "C. 1935" from the catalog
    /// date text, falling back to the bare year.
    private var eraLabel: String? {
        if let dateText = match.photo.dateText { return dateText }
        if let year = match.photo.dateYear { return String(year) }
        return nil
    }

    /// "STRONG MATCH · 80 FT AWAY" — the confidence line, in the
    /// device's locale units.
    private var catalogLine: String {
        let distance = Measurement(value: match.distanceMeters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
        return "\(match.confidenceLabel.rawValue) · \(distance) away"
    }
}
