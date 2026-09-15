import SwiftUI

public struct LibraryHealthDashboardView: View {
    @EnvironmentObject private var health: LibraryHealthProjectionStore
    @EnvironmentObject private var navigation: LibraryNavigationCoordinator
    @Environment(\.colorScheme) private var colorScheme
    @State private var summaryOwner = LibraryContentSummaryOwner()

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Library Health").font(.largeTitle.weight(.semibold))
                    Text("\(knownIssueCount) known issues across metadata and quality checks. File checks run only when you request them.")
                        .foregroundStyle(.secondary)
                }
                dashboardSection("Files", categories: [
                    .missingFiles, .unavailableVolumes, .duplicateTracks,
                ])
                dashboardSection("Missing Metadata", categories: [
                    .missingArtwork, .missingGenre, .missingArtistNames, .missingAlbumNames,
                    .missingTrackNumber, .emptyTitles, .missingYear,
                ])
                dashboardSection("Consistency", categories: [
                    .inconsistentArtists, .inconsistentAlbums, .inconsistentGenres,
                    .inconsistentAlbumArtists,
                ])
                dashboardSection("Cleanup & Quality", categories: [
                    .filledComments, .lowBitrate,
                ])
            }
            .padding(24)
        }
        .background(SongbirdTheme.background(for: colorScheme))
        .onAppear {
            LibraryStatus.shared.summary.activate(owner: summaryOwner, initial: dashboardSummary)
        }
        .onDisappear { LibraryStatus.shared.summary.clear(owner: summaryOwner) }
        .task { health.checkCatalogCategories() }
        .task(id: dashboardSummary) {
            LibraryStatus.shared.summary.update(owner: summaryOwner, summary: dashboardSummary)
        }
    }

    private func dashboardSection(
        _ title: String,
        categories: [LibraryHealthCategory]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.weight(.semibold))
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 190, maximum: 280), spacing: 12)],
                spacing: 12
            ) {
                ForEach(categories, id: \.self) { category in
                    Button {
                        navigation.showHealth(category)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: symbol(for: category))
                                .font(.title3)
                                .frame(width: 26)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(category.displayName)
                                    .font(.headline)
                                    .lineLimit(1)
                                if let count = issueCount(for: category) {
                                    Text("\(count) finding\(count == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundStyle(count == 0 ? .green : .secondary)
                                } else {
                                    Text(statusText(for: category))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var knownIssueCount: Int {
        LibraryHealthCategory.allCases.compactMap { issueCount(for: $0) }.reduce(0, +)
    }

    private var dashboardSummary: LibraryContentSummary {
        let checked = LibraryHealthCategory.allCases.count {
            health.state(for: $0).lastGood != nil
        }
        return .healthDashboard(issueCount: knownIssueCount, checkedCount: checked)
    }

    private func issueCount(for category: LibraryHealthCategory) -> Int? {
        health.state(for: category).lastGood?.findingCount
    }

    private func statusText(for category: LibraryHealthCategory) -> String {
        switch health.state(for: category) {
        case .checking: "Checking…"
        case .failed: "Check failed · Retry"
        case .stale: "Results stale"
        case .notChecked: "Check required"
        case .ready: "Checked"
        }
    }

    private func symbol(for category: LibraryHealthCategory) -> String {
        switch category {
        case .missingFiles: "doc.questionmark"
        case .unavailableVolumes: "externaldrive.badge.exclamationmark"
        case .duplicateTracks: "doc.on.doc"
        case .missingArtwork: "photo.on.rectangle.angled"
        case .missingGenre: "tag.slash"
        case .missingArtistNames: "person.crop.questionmark"
        case .missingAlbumNames: "square.stack.questionmark"
        case .missingTrackNumber: "number"
        case .emptyTitles: "textformat.abc"
        case .missingYear: "calendar.badge.exclamationmark"
        case .inconsistentArtists, .inconsistentAlbumArtists: "person.2.badge.gearshape"
        case .inconsistentAlbums: "square.stack.3d.up.badge.gearshape"
        case .inconsistentGenres: "tag.badge.gearshape"
        case .filledComments: "bubble.left.and.text.bubble.right"
        case .lowBitrate: "waveform.badge.minus"
        }
    }
}
