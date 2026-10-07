import Foundation
import SwiftUI

struct TrackTableFilterState: Equatable {
    var selectedArtist: String?
    var selectedAlbumIDs: Set<String> = []
    var selectedGenre: String?

    var isActive: Bool {
        selectedArtist != nil || !selectedAlbumIDs.isEmpty || selectedGenre != nil
    }

    mutating func remove(_ id: TrackTableFilterChip.ID) {
        switch id {
        case .genre: selectedGenre = nil
        case .artist: selectedArtist = nil
        case .album(let albumID): selectedAlbumIDs.remove(albumID)
        }
    }

    mutating func clear() {
        self = Self()
    }

    func chips(facets: TrackTableFacets) -> [TrackTableFilterChip] {
        var result: [TrackTableFilterChip] = []
        if let selectedGenre {
            result.append(.init(id: .genre, label: "Genre: \(selectedGenre)"))
        }
        if let selectedArtist {
            result.append(.init(id: .artist, label: "Album Artist: \(selectedArtist)"))
        }
        let albums = Dictionary(uniqueKeysWithValues: facets.albums.map { ($0.id, $0) })
        let albumChips = selectedAlbumIDs.map { id in
            let album = albums[id]
            let detail = album?.detail.map { " · \($0)" } ?? ""
            return TrackTableFilterChip(id: .album(id), label: "Album: \(album?.title ?? "Selected Album")\(detail)")
        }.sorted {
            let comparison = $0.label.localizedStandardCompare($1.label)
            if comparison != .orderedSame { return comparison == .orderedAscending }
            return $0.id.stableKey < $1.id.stableKey
        }
        result.append(contentsOf: albumChips)
        return result
    }
}

struct TrackTableFilterChip: Identifiable, Equatable {
    enum ID: Hashable {
        case genre
        case artist
        case album(String)

        var stableKey: String {
            switch self {
            case .genre: "genre"
            case .artist: "artist"
            case .album(let id): "album:\(id)"
            }
        }
    }

    let id: ID
    let label: String
}

struct TrackTableFilterChips: View {
    let chips: [TrackTableFilterChip]
    let resultCount: Int
    let isUpdating: Bool
    let remove: (TrackTableFilterChip.ID) -> Void
    let clear: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(isUpdating ? "Updating…" : "\(resultCount) results")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize()
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(chips) { chip in
                        Button {
                            remove(chip.id)
                        } label: {
                            HStack(spacing: 5) {
                                Text(chip.label).lineLimit(1)
                                Image(systemName: "xmark").imageScale(.small)
                            }
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: 260)
                        .help(chip.label)
                        .accessibilityLabel("Remove \(chip.label) filter")
                    }
                }
            }
            .scrollIndicators(.hidden)
            Button("Clear All", action: clear)
                .buttonStyle(.borderless)
                .font(.caption)
                .fixedSize()
                .help("Clear all browser filters. Search stays unchanged.")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .accessibilityIdentifier("library.activeFilters")
    }
}
