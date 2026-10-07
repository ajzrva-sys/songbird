import SwiftUI

struct AlbumCardPlayButton: View {
    let title: String
    let action: () -> Void
    let isRevealed: Bool
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            Label("Play \(title)", systemImage: "play.fill")
                .labelStyle(.iconOnly)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
            .buttonStyle(AlbumCardPlayButtonStyle(isFocused: isFocused))
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .focused($isFocused)
            .opacity(isRevealed || isFocused ? 1 : 0)
            .allowsHitTesting(isRevealed || isFocused)
            .help("Play \(title)")
            .accessibilityLabel("Play \(title)")
            .accessibilityInputLabels(["Play", "Play \(title)"])
    }
}

private struct AlbumCardPlayButtonStyle: ButtonStyle {
    let isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoverLocation: CGPoint?

    func makeBody(configuration: Configuration) -> some View {
        let isHovered = hoverLocation != nil
        let isHighlighted = isHovered || isFocused
        let isPressed = configuration.isPressed
        let location = hoverLocation ?? CGPoint(x: 22, y: 22)
        let highlightCenter = reduceMotion ? UnitPoint.center : UnitPoint(
            x: min(max(location.x / 44, 0), 1),
            y: min(max(location.y / 44, 0), 1)
        )

        configuration.label
            .background {
                Circle()
                    .fill(.black.opacity(isPressed ? 0.9 : (isHighlighted ? 0.8 : 0.65)))
                    .overlay {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [.white.opacity(0.24), Color.accentColor.opacity(0.2), .clear],
                                    center: highlightCenter,
                                    startRadius: 0,
                                    endRadius: 28
                                )
                            )
                            .opacity(isHighlighted ? 1 : 0)
                    }
            }
            .overlay {
                Circle()
                    .strokeBorder(
                        RadialGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.25)],
                            center: highlightCenter,
                            startRadius: 0,
                            endRadius: 44
                        ),
                        lineWidth: 1.5
                    )
                    .opacity(isHighlighted ? 0.9 : 0)
                    .allowsHitTesting(false)
            }
            .shadow(
                color: .black.opacity(isHighlighted ? 0.35 : 0),
                radius: isPressed ? 2 : 6,
                y: isPressed ? 1 : 3
            )
            .rotation3DEffect(.degrees(Double(0.5 - highlightCenter.y) * 8), axis: (x: 1, y: 0, z: 0))
            .rotation3DEffect(.degrees(Double(highlightCenter.x - 0.5) * 8), axis: (x: 0, y: 1, z: 0))
            .scaleEffect(reduceMotion ? 1 : (isPressed ? 0.94 : (isHighlighted ? 1.08 : 1)))
            .frame(width: 44, height: 44)
            .contentShape(Circle())
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let location): hoverLocation = location
                case .ended: hoverLocation = nil
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isHighlighted)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isHovered)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: isPressed)
    }
}

struct AlbumCardOpenButton: View {
    let title: String
    let textColor: Color
    let action: () -> Void
    var selectionAction: ((NSEvent.ModifierFlags) -> Void)? = nil

    var body: some View {
        Button {
            activate(event: NSApp.currentEvent)
        } label: {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(textColor)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 28, alignment: .leading)
        }
        .buttonStyle(.plain)
        .help("Open \(title)")
        .accessibilityLabel("Open \(title)")
        .accessibilityInputLabels(["Open Album", "Open \(title)"])
    }

    @MainActor
    func activate(event: NSEvent?) {
        if let event,
           event.type == .leftMouseDown || event.type == .leftMouseUp,
           event.modifierFlags.intersection([.command, .shift]).isEmpty == false,
           let selectionAction {
            selectionAction(event.modifierFlags)
        } else {
            action()
        }
    }
}
