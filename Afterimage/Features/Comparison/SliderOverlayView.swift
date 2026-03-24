import SwiftUI

struct SliderOverlayView: View {
    let userPhoto: UIImage
    let historicalPhoto: UIImage

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

                // Divider line
                Rectangle()
                    .fill(.white)
                    .frame(width: 4)
                    .shadow(color: .black.opacity(0.3), radius: 2)
                    .position(x: currentX, y: geo.size.height / 2)

                // Chevron handle on the divider
                HStack(spacing: 2) {
                    Image(systemName: "chevron.left")
                    Image(systemName: "chevron.right")
                }
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 1)
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
        }
    }
}
