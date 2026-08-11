import SwiftUI

/// Afterimage's design language: the archival plate.
///
/// The interface is the dark of a plate archive — cool silver-gelatin
/// surfaces — with museum-label bone for text and one albumen sepia
/// reserved for the historical layer's voice: datelines, era chips,
/// the reveal handle's ring. The present day speaks in neutral bone;
/// only the past is warm.
enum Theme {
    // MARK: - Surfaces

    /// #121316 — unexposed plate; the app's ground.
    static let plate = Color(red: 0.071, green: 0.075, blue: 0.086)
    /// #1B1D21 — raised surfaces: loading plates, overlays.
    static let plateRaised = Color(red: 0.106, green: 0.114, blue: 0.129)
    /// #EFEAE0 — museum label stock.
    static let bone = Color(red: 0.937, green: 0.918, blue: 0.878)

    // MARK: - Text on dark surfaces

    /// #A9A296 — secondary text on plate.
    static let boneMuted = Color(red: 0.663, green: 0.635, blue: 0.588)
    /// #6E6960 — hairlines and registration marks only; below AA for body text.
    static let boneFaint = Color(red: 0.431, green: 0.412, blue: 0.376)
    /// #C9A876 — albumen sepia; the historical layer's accent on dark surfaces.
    static let albumen = Color(red: 0.788, green: 0.659, blue: 0.463)

    // MARK: - Text on bone (the museum label)

    /// #7A5E36 — deep sepia for datelines on label stock (5.0:1 on bone).
    static let albumenDeep = Color(red: 0.478, green: 0.369, blue: 0.212)
    /// #5B564D — muted catalog text on label stock (6.1:1 on bone).
    static let inkOnBone = Color(red: 0.357, green: 0.337, blue: 0.302)

    // MARK: - Type roles

    /// Museum-label title face.
    static let serifTitle = Font.system(.title3, design: .serif).weight(.semibold)
    /// Catalog eyebrow — pair with `EyebrowText` for tracking and caps.
    /// Text-style based so Dynamic Type scales it.
    static let eyebrowFont = Font.system(.caption2, design: .monospaced).weight(.semibold)
    /// Catalog metadata lines.
    static let metaFont = Font.system(.caption, design: .monospaced)
}

// MARK: - EyebrowText

/// Mono-caps catalog eyebrow: "NEW YORK CITY", "TODAY", "C. 1935".
struct EyebrowText: View {
    let text: String
    var color: Color = Theme.boneMuted

    init(_ text: String, color: Color = Theme.boneMuted) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(Theme.eyebrowFont)
            .textCase(.uppercase)
            .tracking(1.5)
            .foregroundStyle(color)
    }
}

// MARK: - EraChip

/// Layer label on the comparison plate: neutral bone for the present,
/// albumen for the historical layer.
struct EraChip: View {
    enum Tone {
        case present, past
    }

    let text: String
    let tone: Tone

    var body: some View {
        EyebrowText(text, color: tone == .past ? Theme.albumen : Theme.bone)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Theme.plate.opacity(0.72), in: RoundedRectangle(cornerRadius: 3))
    }
}

// MARK: - Button styles

/// Primary action: a bone slab, plate-dark mono-caps title.
struct SlabButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            EyebrowText(title, color: Theme.plate)
                .frame(maxWidth: .infinity, minHeight: 48)
                .contentShape(Rectangle())
        }
        .background(Theme.bone, in: RoundedRectangle(cornerRadius: 2))
        .buttonStyle(.plain)
    }
}

/// Secondary action: hairline-framed, bone mono-caps title.
struct GhostButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            EyebrowText(title, color: Theme.bone)
                .frame(maxWidth: .infinity, minHeight: 48)
                .contentShape(Rectangle())
        }
        .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.boneFaint, lineWidth: 1))
        .buttonStyle(.plain)
    }
}

/// Tertiary action: bare mono-caps text, muted.
struct QuietButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            EyebrowText(title, color: Theme.boneMuted)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - PlateFrame

/// The archival-plate mount: hairline border with registration ticks
/// at the corners. Wraps the comparison slider.
struct PlateFrame: ViewModifier {
    func body(content: Content) -> some View {
        content
            .border(Theme.boneFaint.opacity(0.6), width: 1)
            .overlay(alignment: .topLeading) { RegistrationTick(rotation: 0) }
            .overlay(alignment: .topTrailing) { RegistrationTick(rotation: 90) }
            .overlay(alignment: .bottomTrailing) { RegistrationTick(rotation: 180) }
            .overlay(alignment: .bottomLeading) { RegistrationTick(rotation: 270) }
    }
}

extension View {
    func plateFrame() -> some View {
        modifier(PlateFrame())
    }
}

/// One L-shaped registration mark, drawn for the top-leading corner
/// and rotated into place for the other three.
private struct RegistrationTick: View {
    let rotation: Double

    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 10))
            path.addLine(to: .zero)
            path.addLine(to: CGPoint(x: 10, y: 0))
        }
        .stroke(Theme.boneFaint, lineWidth: 1.5)
        .frame(width: 10, height: 10)
        .rotationEffect(.degrees(rotation))
        .offset(x: rotation == 0 || rotation == 270 ? -5 : 5,
                y: rotation == 0 || rotation == 90 ? -5 : 5)
    }
}
