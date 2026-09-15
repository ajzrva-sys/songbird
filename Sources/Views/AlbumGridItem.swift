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

    var body: some View {
        ZStack(alignment: .top) {
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
                colorScheme: colorScheme
            )
            MacClickActivationView(
                singleClick: selectionAction,
                doubleClick: {
                    actions.requestPlay(trackIDs: album.trackIDs)
                }
            )
        }
        .contentShape(.rect)
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 3)
                .padding(-4)
                .accessibilityHidden(true)
        }
        .focusable()
        .onKeyPress(.return) {
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
