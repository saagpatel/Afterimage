import SwiftUI

struct SliderOverlayView: View {
    let userPhoto: UIImage
    let historicalPhoto: UIImage
    var eraLabel: String?

    @State private var dividerX: CGFloat = 0
    @GestureState private var dragOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let currentX = min(max(dividerX + dragOffset, 0), geo.size.width)

            ZStack {
                // Bottom layer: historical photo (full width, always visible)
                Image(uiImage: historicalPhoto)
                    .resizable()
                    .aspectRatio(4.0 / 3.0, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Top layer: user photo masked to the left of the divider
                Image(uiImage: userPhoto)
                    .resizable()
                    .aspectRatio(4.0 / 3.0, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: currentX)
                    }

                // Layer labels: the present in bone, the past in albumen
                VStack {
                    HStack {
                        EraChip(text: "Today", tone: .present)
                        Spacer()
                        if let eraLabel {
                            EraChip(text: eraLabel, tone: .past)
                        }
                    }
                    Spacer()
                }
                .padding(10)

                // Divider hairline
                Rectangle()
                    .fill(Theme.bone)
                    .frame(width: 2)
                    .shadow(color: .black.opacity(0.35), radius: 2)
                    .position(x: currentX, y: geo.size.height / 2)

                // Reveal handle on the divider
                ZStack {
                    Circle()
                        .fill(Theme.bone)
                        .frame(width: 34, height: 34)
                        .shadow(color: .black.opacity(0.35), radius: 3)
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
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($dragOffset) { value, state, _ in
                        state = value.translation.width
                    }
                    .onEnded { value in
                        dividerX = min(max(dividerX + value.translation.width, 0), geo.size.width)
                    }
            )
            .onAppear {
                dividerX = geo.size.width / 2
            }
            // One adjustable VoiceOver element: swipe up/down moves the
            // divider, since the drag gesture itself is not accessible.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Comparison slider")
            .accessibilityValue(revealDescription(at: currentX, width: geo.size.width))
            .accessibilityAdjustableAction { direction in
                let step = geo.size.width / 10
                switch direction {
                case .increment:
                    dividerX = min(dividerX + step, geo.size.width)
                case .decrement:
                    dividerX = max(dividerX - step, 0)
                @unknown default:
                    break
                }
            }
            .accessibilityIdentifier("comparison-slider")
        }
    }

    private func revealDescription(at x: CGFloat, width: CGFloat) -> String {
        let percent = Int((x / max(width, 1)) * 100)
        return "\(percent) percent today, \(100 - percent) percent historical"
    }
}
