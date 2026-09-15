import SwiftUI

public struct FeatherDockIconPicker: View {
    public let theme: SongbirdThemeID
    @State private var selection: SongbirdDockIconChoice

    public init(theme: SongbirdThemeID) {
        self.theme = theme
        _selection = State(
            initialValue: SongbirdDockIconPreference.choice(for: theme)
                ?? .blueOutline
        )
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Dock Icon")
                .font(.headline)

            HStack(spacing: 10) {
                ForEach(theme.dockIconChoices) { choice in
                    FeatherDockIconChoiceButton(
                        choice: choice,
                        isSelected: selection == choice,
                        action: { select(choice) }
                    )
                }
            }

            Text("Choose the Dock icon used with this Feather.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func select(_ choice: SongbirdDockIconChoice) {
        selection = choice
        SongbirdDockIconPreference.setChoice(choice, for: theme)
        SongbirdDockIconManager.apply(for: theme)
    }
}
