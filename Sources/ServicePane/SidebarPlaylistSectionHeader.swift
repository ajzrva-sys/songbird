import SwiftUI

struct SidebarPlaylistSectionHeader: View {
    let targetRequest: SidebarPlaylistTargetRequest?
    let isExpanded: Bool
    let foregroundColor: Color
    var metrics: ServicePaneMetrics = .standard
    let onToggleExpanded: () -> Void
    let onNewPlaylist: () -> Void
    let onNewSmartPlaylist: () -> Void
    let onCancelTargeting: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onToggleExpanded) {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 10)
                    Text(targetRequest == nil ? "PLAYLISTS" : "ADD TO PLAYLIST")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.5)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            if targetRequest != nil {
                Button("Create Playlist", systemImage: "plus", action: onNewPlaylist)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .frame(width: 18, height: 18)
                    .help("Create a playlist with this album")

                Button("Cancel", systemImage: "xmark", action: onCancelTargeting)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .frame(width: 18, height: 18)
                    .help("Cancel choosing a playlist")
            } else {
                Menu {
                    Button("New Playlist…", systemImage: "music.note.list", action: onNewPlaylist)
                    Button(
                        "New Smart Playlist…",
                        systemImage: "gearshape.2",
                        action: onNewSmartPlaylist
                    )
                } label: {
                    Label("Add Playlist", systemImage: "plus")
                        .labelStyle(.iconOnly)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Add Playlist")
            }
        }
        .foregroundStyle(foregroundColor)
        .padding(.leading, 8)
        .padding(.trailing, metrics.horizontalInset)
        .padding(.top, metrics.sectionSpacing / 2)
        .padding(.bottom, metrics.sectionSpacing / 2)
        .frame(maxWidth: .infinity)
    }
}
