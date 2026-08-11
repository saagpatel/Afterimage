import SwiftUI
import UniformTypeIdentifiers

// MARK: - Era label

extension MatchCandidate {
    /// Chip text for the historical layer: "C. 1935" from the catalog
    /// date text, falling back to the bare year.
    var eraLabel: String? {
        if let dateText = photo.dateText { return dateText }
        if let year = photo.dateYear { return String(year) }
        return nil
    }
}

// MARK: - MuseumLabelCard

/// The bone label card under the plate: city eyebrow, serif title,
/// sepia dateline, confidence line, attribution, wordmark. Shared by
/// the comparison screen and the share export.
struct MuseumLabelCard: View {
    let match: MatchCandidate

    var body: some View {
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

    /// "STRONG MATCH · 80 FT AWAY" — the confidence line, in the
    /// device's locale units.
    private var catalogLine: String {
        let distance = Measurement(value: match.distanceMeters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
        return "\(match.confidenceLabel.rawValue) · \(distance) away"
    }
}

// MARK: - SharePlateView

/// The exported composition: the mounted plate frozen at the viewer's
/// reveal position, over the museum label. Rendered off-screen by
/// `PlateExport` — fixed width, default type sizes.
struct SharePlateView: View {
    let userPhoto: UIImage
    let historicalPhoto: UIImage
    let match: MatchCandidate
    let revealFraction: CGFloat

    /// Logical canvas width; rendered at 2x for a 1080px-wide image.
    static let canvasWidth: CGFloat = 540

    var body: some View {
        VStack(spacing: 20) {
            frozenPlate
                .aspectRatio(4.0 / 3.0, contentMode: .fit)
                .plateFrame()

            MuseumLabelCard(match: match)
        }
        .padding(24)
        .frame(width: Self.canvasWidth)
        .background(Theme.plate)
    }

    private var frozenPlate: some View {
        GeometryReader { geo in
            let currentX = min(max(revealFraction, 0), 1) * geo.size.width

            ZStack {
                Image(uiImage: historicalPhoto)
                    .resizable()
                    .aspectRatio(4.0 / 3.0, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Image(uiImage: userPhoto)
                    .resizable()
                    .aspectRatio(4.0 / 3.0, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: currentX)
                    }

                VStack {
                    HStack {
                        EraChip(text: "Today", tone: .present)
                        Spacer()
                        if let eraLabel = match.eraLabel {
                            EraChip(text: eraLabel, tone: .past)
                        }
                    }
                    Spacer()
                }
                .padding(10)

                Rectangle()
                    .fill(Theme.bone)
                    .frame(width: 2)
                    .position(x: currentX, y: geo.size.height / 2)

                ZStack {
                    Circle()
                        .fill(Theme.bone)
                        .frame(width: 34, height: 34)
                    Circle()
                        .stroke(Theme.albumen, lineWidth: 1.5)
                        .frame(width: 28, height: 28)
                    HStack(spacing: 1) {
                        Image(systemName: "chevron.left")
                        Image(systemName: "chevron.right")
                    }
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.plate)
                }
                .position(x: currentX, y: geo.size.height / 2)
            }
        }
    }
}

// MARK: - PlateExport

/// Transferable payload for the share sheet. Rendering happens lazily
/// at share time, so dragging the slider costs nothing.
/// Sendable: UIImage is immutable and Sendable; all other members are
/// value types.
struct PlateExport: Transferable, Sendable {
    let userPhoto: UIImage
    let historicalPhoto: UIImage
    let match: MatchCandidate
    let revealFraction: CGFloat

    enum ExportError: Error {
        case renderFailed
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { export in
            try await export.renderPNG()
        }
        .suggestedFileName("afterimage.png")
    }

    @MainActor
    func renderPNG() throws -> Data {
        // ImageRenderer does not inherit the app's environment; pin the
        // scheme so the export stays identical if any system-styled
        // element is ever added to the composition.
        let renderer = ImageRenderer(
            content: SharePlateView(
                userPhoto: userPhoto,
                historicalPhoto: historicalPhoto,
                match: match,
                revealFraction: revealFraction
            )
            .environment(\.colorScheme, .dark)
        )
        renderer.scale = 2
        guard let data = renderer.uiImage?.pngData() else {
            throw ExportError.renderFailed
        }
        return data
    }
}
