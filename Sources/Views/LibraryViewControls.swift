import SwiftUI

/// Shared native menu content for the toolbar, table header, and application menu.
public struct TrackTableColumnMenuItems: View {
    @Binding private var preferencesRaw: String

    public init(preferencesRaw: Binding<String>) {
        _preferencesRaw = preferencesRaw
    }

    public var body: some View {
        ForEach(TrackTableColumnPrefs.decode(preferencesRaw).sorted {
            ($0.column?.label ?? $0.id).localizedCaseInsensitiveCompare($1.column?.label ?? $1.id)
                == .orderedAscending
        }) { preference in
            if let column = preference.column, column.isSupported {
                Toggle(column.label, isOn: Binding(
                    get: { column == .title || preference.visible },
                    set: { visible in
                        var preferences = TrackTableColumnPrefs.decode(preferencesRaw)
                        TrackTableColumnPrefs.setVisible(&preferences, column: column, visible: visible)
                        preferencesRaw = TrackTableColumnPrefs.encode(preferences)
                    }
                ))
                .disabled(column == .title)
            }
        }
        Divider()
        Button("Reset Columns") {
            preferencesRaw = TrackTableColumnPrefs.encode(TrackTableColumnPrefs.defaults)
        }
    }
}

struct TrackTableViewMenu: View {
    @Binding var preferencesRaw: String
    @Binding var presentationRaw: String
    @Binding var browserVisible: Bool
    let showsBrowserOption: Bool

    var body: some View {
        Menu {
            Picker("Density", selection: $presentationRaw) {
                ForEach(TrackTablePresentation.allCases, id: \.rawValue) { presentation in
                    Text(presentation.displayName).tag(presentation.rawValue)
                }
            }
            Menu("Columns") {
                TrackTableColumnMenuItems(preferencesRaw: $preferencesRaw)
            }
            if showsBrowserOption {
                Divider()
                Toggle("Show Filter Browser", isOn: $browserVisible)
            }
        } label: {
            Label("View", systemImage: "slider.horizontal.3")
        }
        .fixedSize()
        .accessibilityIdentifier("library.tableViewOptions")
    }
}

struct AlbumGridViewControls: View {
    @Binding var artworkSize: Double
    @Binding var gridSpacing: Double
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Label("View", systemImage: "slider.horizontal.3")
        }
        .accessibilityIdentifier("library.albumViewOptions")
        .popover(isPresented: $isPresented) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Album View").font(.headline)
                LabeledContent("Artwork Size") {
                    Text("\(Int(AlbumGridSettings.normalizedArtworkSize(artworkSize))) pt")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: Binding(
                    get: { AlbumGridSettings.normalizedArtworkSize(artworkSize) },
                    set: { artworkSize = AlbumGridSettings.normalizedArtworkSize($0) }
                ), in: AlbumGridSettings.artworkSizeRange, step: AlbumGridSettings.artworkSizeStep) {
                    Text("Album artwork size")
                }
                .labelsHidden()
                .accessibilityLabel("Album artwork size")
                LabeledContent("Grid Spacing") {
                    Text("\(Int(AlbumGridSettings.normalizedGridSpacing(gridSpacing))) pt")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: Binding(
                    get: { AlbumGridSettings.normalizedGridSpacing(gridSpacing) },
                    set: { gridSpacing = AlbumGridSettings.normalizedGridSpacing($0) }
                ), in: AlbumGridSettings.gridSpacingRange, step: AlbumGridSettings.gridSpacingStep) {
                    Text("Album grid spacing")
                }
                .labelsHidden()
                .accessibilityLabel("Album grid spacing")
            }
            .padding(16)
            .frame(width: 300)
            .accessibilityIdentifier("library.albumViewPopover")
        }
    }
}
