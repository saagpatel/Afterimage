import SwiftUI
import UIKit

struct ComparisonView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case slider = "Slider"
        case sideBySide = "Side by Side"
        case fade = "Fade"

        var id: Self { self }
    }

    let userPhoto: UIImage
    let matches: [MatchCandidate]
    let onDismiss: () -> Void

    @State private var selectedIndex = 0
    @State private var mode: Mode = .slider
    @State private var fadeAmount = 0.5
    @State private var shareImage: ShareImage?

    private var selectedMatch: MatchCandidate {
        matches[min(selectedIndex, matches.count - 1)]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Picker("Comparison mode", selection: $mode) {
                        ForEach(Mode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    comparisonHero
                        .aspectRatio(4.0 / 3.0, contentMode: .fit)
                        .accessibilityIdentifier("comparison-hero")

                    if matches.count > 1 {
                        matchPicker
                    }

                    attributionPanel

                    Button {
                        guard let historicalPhoto = selectedMatch.thumbnail else { return }
                        shareImage = ShareImage(image: ShareCompositor.render(
                            presentDay: userPhoto,
                            historical: historicalPhoto,
                            caption: shareCaption
                        ))
                    } label: {
                        Label("Share Comparison", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedMatch.thumbnail == nil)
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .background(.black)
            .foregroundStyle(.white)
            .navigationTitle("Afterimage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Back", systemImage: "chevron.left", action: onDismiss)
                }
            }
        }
        .sheet(item: $shareImage) { item in
            ShareSheet(items: [item.image])
        }
    }

    @ViewBuilder
    private var comparisonHero: some View {
        if let historicalPhoto = selectedMatch.thumbnail {
            switch mode {
            case .slider:
                SliderOverlayView(userPhoto: userPhoto, historicalPhoto: historicalPhoto)
            case .sideBySide:
                HStack(spacing: 2) {
                    comparisonImage(userPhoto, label: "Present day")
                    comparisonImage(historicalPhoto, label: "Historical")
                }
            case .fade:
                VStack(spacing: 12) {
                    ZStack {
                        comparisonImage(historicalPhoto, label: "Historical photograph")
                        comparisonImage(userPhoto, label: "Present-day photograph")
                            .opacity(fadeAmount)
                    }
                    Slider(value: $fadeAmount, in: 0...1)
                        .accessibilityLabel("Present-day photo opacity")
                        .accessibilityValue("\(Int(fadeAmount * 100)) percent")
                        .padding(.horizontal)
                }
            }
        } else {
            ContentUnavailableView(
                "Image Unavailable",
                systemImage: "photo.badge.exclamationmark",
                description: Text("Choose another match or try again when connected.")
            )
        }
    }

    private func comparisonImage(_ image: UIImage, label: String) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .clipped()
            .accessibilityLabel(label)
    }

    private var matchPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Other matches")
                .font(.headline)
                .padding(.horizontal)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 12) {
                    ForEach(Array(matches.enumerated()), id: \.element.id) { index, match in
                        Button {
                            selectedIndex = index
                        } label: {
                            Group {
                                if let thumbnail = match.thumbnail {
                                    Image(uiImage: thumbnail)
                                        .resizable()
                                        .scaledToFill()
                                } else {
                                    Image(systemName: "photo")
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .background(.white.opacity(0.1))
                                }
                            }
                            .frame(width: 96, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(index == selectedIndex ? .white : .clear, lineWidth: 3)
                            }
                        }
                        .accessibilityLabel("Match \(index + 1): \(match.photo.title)")
                        .accessibilityValue(index == selectedIndex ? "Selected" : "")
                    }
                }
                .padding(.horizontal)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var attributionPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(selectedMatch.photo.title)
                .font(.headline)
            if let dateText = selectedMatch.photo.dateText {
                Text(dateText)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
            }
            Text(selectedMatch.photo.attribution)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
            Text(selectedMatch.confidenceLabel.rawValue)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.white.opacity(0.15), in: Capsule())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
    }

    private var shareCaption: String {
        [selectedMatch.photo.title, selectedMatch.photo.dateText, selectedMatch.photo.attribution]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

private struct ShareImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

enum ShareCompositor {
    static func render(presentDay: UIImage, historical: UIImage, caption: String) -> UIImage {
        let size = CGSize(width: 1_200, height: 800)
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            drawAspectFill(
                presentDay,
                in: CGRect(x: 0, y: 0, width: 600, height: 720),
                context: context.cgContext
            )
            drawAspectFill(
                historical,
                in: CGRect(x: 600, y: 0, width: 600, height: 720),
                context: context.cgContext
            )

            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.preferredFont(forTextStyle: .footnote),
                .foregroundColor: UIColor.white,
            ]
            NSString(string: caption).draw(
                in: CGRect(x: 32, y: 742, width: 1_136, height: 40),
                withAttributes: attributes
            )
        }
    }

    private static func drawAspectFill(_ image: UIImage, in bounds: CGRect, context: CGContext) {
        context.saveGState()
        context.clip(to: bounds)
        image.draw(in: aspectFillRect(for: image.size, inside: bounds))
        context.restoreGState()
    }

    private static func aspectFillRect(for imageSize: CGSize, inside bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return bounds }
        let scale = max(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let renderedSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: bounds.midX - renderedSize.width / 2,
            y: bounds.midY - renderedSize.height / 2,
            width: renderedSize.width,
            height: renderedSize.height
        )
    }
}
