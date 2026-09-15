import SwiftUI

struct FeatherDockIconPreview: View {
    let choice: SongbirdDockIconChoice

    var body: some View {
        Group {
            if let image = SongbirdDockIconManager.image(for: choice) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(.black)
                    .overlay {
                        Image(systemName: "bird.fill")
                            .foregroundStyle(.white)
                    }
            }
        }
        .frame(width: 64, height: 64)
        .clipped()
        .accessibilityHidden(true)
    }
}
