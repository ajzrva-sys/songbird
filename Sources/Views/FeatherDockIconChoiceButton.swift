import SwiftUI

struct FeatherDockIconChoiceButton: View {
    let choice: SongbirdDockIconChoice
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    FeatherDockIconPreview(choice: choice)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.accentColor)
                            .padding(3)
                            .accessibilityHidden(true)
                    }
                }
                Text(choice.displayName)
                    .lineLimit(1)
            }
            .frame(width: 104)
            .padding(8)
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(
                    isSelected ? Color.accentColor : Color.secondary.opacity(0.28),
                    lineWidth: isSelected ? 2 : 1
                )
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("Uses this icon with the \(choiceThemeName) Feather")
    }

    private var choiceThemeName: String {
        switch choice {
        case .blueOutline, .blueVinyl: return SongbirdThemeID.blueMonday.displayName
        case .gonzoLight, .gonzoDark: return SongbirdThemeID.gonzo.displayName
        case .pinkLacquer, .pinkBurgundy, .pinkTerrazzo:
            return SongbirdThemeID.pinkMartini.displayName
        case .bowieSilverBlue, .bowiePrism:
            return SongbirdThemeID.bowie.displayName
        case .dovePearl, .doveMarble:
            return SongbirdThemeID.dove.displayName
        case .silverwingFrame, .silverwingGraphite:
            return SongbirdThemeID.silverwing.displayName
        case .musicLightLacquer:
            return SongbirdThemeID.musicLight.displayName
        case .musicDarkRed:
            return SongbirdThemeID.musicDark.displayName
        case .purpleRim, .purpleNeon: return SongbirdThemeID.purpleRain.displayName
        case .nightingaleGlow, .nightingaleGlass:
            return SongbirdThemeID.nightingale.displayName
        case .blackbirdGraphite, .blackbirdAmber:
            return SongbirdThemeID.blackbird.displayName
        case .terminalAmber:
            return SongbirdThemeID.terminal.displayName
        }
    }
}
