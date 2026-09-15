import SwiftUI
import SwiftData

/// Library health view showing groups of artist, album, album artist, or genre
/// names that differ only by casing or minor variations.
public struct InconsistentNamesView: View {
    public enum Mode {
        case artist
        case album
        case genre
        case albumArtist
    }

    let mode: Mode

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @State private var groups: [NameGroup] = []
    @State private var isLoading = true
    @State private var mergeTarget: MergeTarget?

    private struct NameGroup: Identifiable {
        let key: String
        let variants: [Variant]
        var id: String { key }

        struct Variant: Identifiable {
            let name: String
            let trackCount: Int
            var id: String { name }
        }
    }

    private struct MergeTarget: Identifiable {
        let group: NameGroup
        let canonical: String
        var id: String { group.key }
    }

    public init(mode: Mode) {
        self.mode = mode
    }

    public var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                Spacer()
                ProgressView("Scanning…")
                Spacer()
            } else if groups.isEmpty {
                Spacer()
                ContentUnavailableView(
                    noItemsTitle,
                    systemImage: noItemsIcon,
                    description: Text(noItemsDescription)
                )
                Spacer()
            } else {
                groupList
            }
        }
        .background(SongbirdTheme.background(for: colorScheme))
        .task { await loadGroups() }
        .confirmationDialog(
            "Merge Names?",
            isPresented: Binding(
                get: { mergeTarget != nil },
                set: { if !$0 { mergeTarget = nil } }
            ),
            presenting: mergeTarget
        ) { target in
            Button("Apply \"\(target.canonical)\" to All") {
                applyMerge(target)
            }
            Button("Cancel", role: .cancel) {}
        } message: { target in
            let count = target.group.variants.count
            Text("\(count) name variant\(count == 1 ? "" : "s") will be unified to \"\(target.canonical)\".")
        }
    }

    private var groupList: some View {
        List {
            Section {
                HStack {
                    Text("\(groups.count) inconsistent group\(groups.count == 1 ? "" : "s")")
                        .font(.headline)
                    Spacer()
                    Button("Fix All…") {
                        fixAll()
                    }
                    .buttonStyle(.bordered)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            ForEach(groups) { group in
                Section {
                    ForEach(group.variants) { variant in
                        HStack {
                            Text(variant.name)
                                .font(.system(size: 13))
                            Spacer()
                            Text("\(variant.trackCount) track\(variant.trackCount == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if variant.name == group.variants.first?.name {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.caption)
                                    .help("Will be kept as canonical")
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    HStack {
                        Text(groupHeader(group))
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Button("Merge…") {
                            if let canonical = group.variants.first?.name {
                                mergeTarget = MergeTarget(group: group, canonical: canonical)
                            }
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .scrollContentBackground(.hidden)
    }

    private func groupHeader(_ group: NameGroup) -> String {
        let total = group.variants.reduce(0) { $0 + $1.trackCount }
        return "\(group.variants.count) variants · \(total) tracks total"
    }

    private var noItemsTitle: String {
        switch mode {
        case .artist: return "No Inconsistent Artists"
        case .album: return "No Inconsistent Albums"
        case .genre: return "No Inconsistent Genres"
        case .albumArtist: return "No Inconsistent Album Artists"
        }
    }

    private var noItemsIcon: String {
        switch mode {
        case .artist: return "person.2.badge.gearshape"
        case .album: return "square.stack.3d.up.badge.gearshape"
        case .genre: return "tag.badge.gearshape"
        case .albumArtist: return "person.2.crop.artframe"
        }
    }

    private var noItemsDescription: String {
        switch mode {
        case .artist: return "All artist names are consistently cased."
        case .album: return "All album names are consistently cased."
        case .genre: return "All genre names are consistently cased."
        case .albumArtist: return "All album artist names are consistently cased."
        }
    }

    @MainActor
    private func loadGroups() async {
        let descriptor = FetchDescriptor<Track>()
        let tracks: [Track]
        do {
            tracks = try modelContext.fetch(descriptor)
        } catch {
            groups = []
            isLoading = false
            return
        }

        let names: [String] = tracks.map { track in
            switch mode {
            case .artist: return track.artist
            case .album: return track.album
            case .genre: return track.genre
            case .albumArtist: return track.albumArtist
            }
        }

        var byLowercase: [String: [String: Int]] = [:]
        for name in names {
            guard !name.isEmpty else { continue }
            let key = name.lowercased()
            byLowercase[key, default: [:]][name, default: 0] += 1
        }

        let result = byLowercase.compactMap { key, variants -> NameGroup? in
            guard variants.count > 1 else { return nil }
            let sorted = variants.sorted { $0.value > $1.value }
                .map { NameGroup.Variant(name: $0.key, trackCount: $0.value) }
            return NameGroup(key: key, variants: sorted)
        }.sorted { $0.key < $1.key }

        groups = result
        isLoading = false
    }

    private func applyMerge(_ target: MergeTarget) {
        mergeTarget = nil
        let canonical = target.canonical
        let lowercase = target.group.key
        let descriptor = FetchDescriptor<Track>()
        guard let tracks = try? modelContext.fetch(descriptor) else { return }

        var changed = 0
        for track in tracks {
            let fieldValue: String
            switch mode {
            case .artist: fieldValue = track.artist
            case .album: fieldValue = track.album
            case .genre: fieldValue = track.genre
            case .albumArtist: fieldValue = track.albumArtist
            }
            if fieldValue.lowercased() == lowercase, fieldValue != canonical {
                switch mode {
                case .artist: track.artist = canonical
                case .album: track.album = canonical
                case .genre: track.genre = canonical
                case .albumArtist: track.albumArtist = canonical
                }
                changed += 1
            }
        }

        do {
            try modelContext.save()
            LibraryStatus.shared.showNotice(
                "Unified \(changed) track\(changed == 1 ? "" : "s") to \"\(canonical)\".",
                severity: .information,
                autoDismissAfter: 4
            )
            Task { await loadGroups() }
        } catch {
            modelContext.rollback()
            LibraryStatus.shared.showPlaybackError("Could not merge names: \(error.localizedDescription)")
        }
    }

    private func fixAll() {
        var totalChanged = 0
        for group in groups {
            guard let canonical = group.variants.first?.name else { continue }
            let lowercase = group.key
            let descriptor = FetchDescriptor<Track>()
            guard let tracks = try? modelContext.fetch(descriptor) else { continue }

            for track in tracks {
                let fieldValue: String
                switch mode {
                case .artist: fieldValue = track.artist
                case .album: fieldValue = track.album
                case .genre: fieldValue = track.genre
                case .albumArtist: fieldValue = track.albumArtist
                }
                if fieldValue.lowercased() == lowercase, fieldValue != canonical {
                    switch mode {
                    case .artist: track.artist = canonical
                    case .album: track.album = canonical
                    case .genre: track.genre = canonical
                    case .albumArtist: track.albumArtist = canonical
                    }
                    totalChanged += 1
                }
            }
        }

        do {
            try modelContext.save()
            LibraryStatus.shared.showNotice(
                "Unified \(totalChanged) track\(totalChanged == 1 ? "" : "s") across \(groups.count) group\(groups.count == 1 ? "" : "s").",
                severity: .information,
                autoDismissAfter: 4
            )
            Task { await loadGroups() }
        } catch {
            modelContext.rollback()
            LibraryStatus.shared.showPlaybackError("Could not merge names: \(error.localizedDescription)")
        }
    }
}
