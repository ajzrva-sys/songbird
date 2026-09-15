import SwiftUI

/// Repeating horizontal lines that simulate an LCD pixel grid.
/// Used as an overlay on the faceplate to give a hardware-display feel.
struct ScanlineTexture: View {
    var opacity: Double = 0.03

    var body: some View {
        Canvas { ctx, size in
            var y: CGFloat = 0
            while y < size.height {
                ctx.fill(
                    Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                    with: .color(.black.opacity(opacity))
                )
                y += 2
            }
        }
    }
}
