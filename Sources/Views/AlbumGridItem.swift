import SwiftUI

struct AlbumGridItem: View {
    let album: LibraryAlbumGroupSnapshot
    let artworkSize: CGFloat
    let displayDetail: String?
    let textColor: Color
    let secondaryTextColor: Color
    let colorScheme: ColorScheme
    let isSelected: Bool
    let contextAlbums: () -> [LibraryAlbumGroupSnapshot]
    let selectionAction: (NSEvent.ModifierFlags) -> Void
    let openAction: () -> Void
    let refreshMetadataAction: () -> Void
    let deleteAction: () -> Void

    @EnvironmentObject private var actions: LibraryItemActionHandler
    @State private var isHovered = false
    @FocusState private var cardFocused: Bool

    var body: some View {
        AlbumCard(
                title: album.title,
                artist: album.artist,
                artworkSize: artworkSize,
                displayDetail: displayDetail,
                discCount: album.discCount,
                isFavorite: album.isFavorite,
                artworkReference: album.artworkReference,
                textColor: textColor,
                secondaryTextColor: secondaryTextColor,
                colorScheme: colorScheme,
                selectionAction: selectionAction,
                openAction: openAction,
                playAction: { actions.requestPlay(trackIDs: album.trackIDs) },
                showsPlayAction: isHovered || isSelected || cardFocused
            )
        .contentShape(.rect)
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(outlineColor, lineWidth: 3)
                .padding(-4)
                .accessibilityHidden(true)
        }
        .focusable()
        .focusEffectDisabled(cardFocused)
        .focused($cardFocused)
        .onHover { isHovered = $0 }
        .onKeyPress(.return) {
            guard cardFocused else { return .ignored }
            openAction()
            return .handled
        }
        .contextMenu {
            AlbumContextMenu(
                albums: contextAlbums(),
                refreshMetadataAction: refreshMetadataAction,
                deleteAction: deleteAction
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(albumAccessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: isSelected ? "Deselect Album" : "Select Album") {
            selectionAction(.command)
        }
        .accessibilityAction(named: "Open Album", openAction)
        .accessibilityAction(named: "Play") {
            actions.requestPlay(trackIDs: album.trackIDs)
        }
        .accessibilityAction(named: "Add to Queue") {
            actions.addToQueue(trackIDs: album.trackIDs)
        }
        .accessibilityAction(named: "Add to New Playlist") {
            actions.requestNewPlaylist(trackIDs: album.trackIDs)
        }
        .accessibilityAction(named: "Delete Album", deleteAction)
    }

    private var outlineColor: Color {
        if isSelected { return .accentColor }
        return cardFocused ? Color.accentColor.opacity(0.5) : .clear
    }

    private var albumAccessibilityLabel: String {
        let discs = album.discCount > 1 ? ", \(album.discCount) discs" : ""
        return "\(album.title), \(album.artist)\(discs)"
    }

    private var accessibilityValue: String {
        [isSelected ? "Selected" : nil, album.isFavorite ? "Favorite" : nil]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}
