import SwiftUI

struct ComparisonView: View {
    let userPhoto: UIImage
    let match: MatchCandidate
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Top navigation bar
            HStack {
                Button(action: onDismiss) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .foregroundStyle(.white)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // Slider hero
            if let thumbnail = match.thumbnail {
                SliderOverlayView(userPhoto: userPhoto, historicalPhoto: thumbnail)
            } else {
                // Thumbnail not yet loaded — show loading state
                Color.gray.opacity(0.3)
                    .aspectRatio(4.0 / 3.0, contentMode: .fit)
                    .overlay {
                        ProgressView()
                            .tint(.white)
                    }
            }

            // Attribution panel
            VStack(alignment: .leading, spacing: 4) {
                Text(match.photo.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)

                if let dateText = match.photo.dateText {
                    Text(dateText)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }

                Text(match.photo.attribution)
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)

            Spacer()
        }
        .background(.black)
        .foregroundStyle(.white)
    }
}
