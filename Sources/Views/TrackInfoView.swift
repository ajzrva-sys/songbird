import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

enum TrackInfoArtworkUpdate: Equatable {
    case unchanged
    case clear
    case replace(Data)

    static func resolve(wasEdited: Bool, wasCleared: Bool, data: Data?) -> Self {
        guard wasEdited else { return .unchanged }
        if wasCleared { return .clear }
        return data.map(Self.replace) ?? .unchanged
    }
}

@MainActor
fileprivate final class TrackInfoCloseState: ObservableObject {
    @Published var isDirty = false
    @Published var isSaving = false
    var allowsClose = false
}

/// Metadata editor for one or more tracks — mirrors the classic Songbird Track Editor
/// (fields + album artwork with Add/Replace, Clear, and drag-drop).
public struct TrackInfoView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var libraryActions: LibraryItemActionHandler

    private let trackTargets: [TrackInfoTarget]
    private let closeState: TrackInfoCloseState

    private var relatedAlbumID: UUID? {
        if let artworkScope, Set(artworkScope.targets.map(\.groupID)).count == 1 {
            return artworkScope.targets.compactMap(\.albumID).first
        }
        let albumIDs = trackTargets.compactMap(\.albumID)
        guard albumIDs.count == trackTargets.count,
              Set(albumIDs).count == 1 else { return nil }
        return albumIDs.first
    }

    var onClose: () -> Void = {}

    @State private var title: String = ""
    @State private var artist: String = ""
    @State private var album: String = ""
    @State private var albumArtist: String = ""
    @State private var genre: String = ""
    @State private var composer: String = ""
    @State private var comment: String = ""
    @State private var year: String = ""
    @State private var trackNumber: String = ""
    @State private var trackTotal: String = ""
    @State private var discNumber: String = ""
    @State private var discTotal: String = ""
    @State private var beatsPerMinute: String = ""
    @State private var rating: Int = 0
    @State private var isLoved = false
    @State private var mixedFields: Set<String> = []
    @State private var editedFields: Set<String> = []

    /// Edited artwork bytes; `nil` means leave unchanged when multi-select mixed.
    @State private var artworkData: Data?
    @State private var artworkRevision = UUID()
    @State private var artworkMixed = false
    @State private var artworkCleared = false
    @State private var artworkEdited = false
    @State private var isDropTargeted = false
    @State private var artworkError: String?
    @State private var artworkScope: TrackArtworkScope?
    @State private var artworkTasks = ViewTaskSlot()
    @State private var artworkLoader = ArtworkInputLoader()
    @State private var isCalculatingBPM = false
    @State private var metadataConflicts: [TrackMetadataConflict] = []
    @State private var conflictResolutions: [String: TrackMetadataConflictResolution] = [:]
    @State private var confirmsDiscard = false
    @State private var isSaving = false
    @State private var saveError: String?

    private var isMulti: Bool { trackTargets.count > 1 }
    private var secondaryColor: Color { SongbirdTheme.secondaryText(for: colorScheme) }
    private var yearError: String? {
        numericError(year, label: "Year", range: 0...9999)
    }
    private var trackNumberError: String? {
        numericError(trackNumber, label: "Track Number", range: 0...9999)
    }
    private var trackTotalError: String? {
        numericError(trackTotal, label: "Track Total", range: 0...9999)
    }
    private var discNumberError: String? {
        numericError(discNumber, label: "Disc Number", range: 0...9999)
    }
    private var discTotalError: String? {
        numericError(discTotal, label: "Disc Total", range: 0...9999)
    }
    private var beatsPerMinuteError: String? {
        numericError(beatsPerMinute, label: "BPM", range: 0...999)
    }
    private var validationErrors: [String] {
        [yearError, trackNumberError, trackTotalError, discNumberError,
         discTotalError, beatsPerMinuteError].compactMap { $0 }
    }
    private var canSave: Bool {
        validationErrors.isEmpty && (!artworkEdited || artworkScope != nil)
    }

    private var hasArtwork: Bool {
        !artworkCleared && artworkData != nil
    }

    @MainActor
    public init(
        tracks: [Track],
        lovedTrackIDs: Set<UUID> = [],
        onClose: @escaping () -> Void = {}
    ) {
        self.init(
            tracks: tracks,
            lovedTrackIDs: lovedTrackIDs,
            closeState: TrackInfoCloseState(),
            onClose: onClose
        )
    }

    @MainActor
    fileprivate init(
        tracks: [Track],
        lovedTrackIDs: Set<UUID>,
        closeState: TrackInfoCloseState,
        onClose: @escaping () -> Void
    ) {
        var seen = Set<UUID>()
        trackTargets = tracks.compactMap { track in
            guard seen.insert(track.id).inserted else { return nil }
            return TrackInfoTarget(track: track, isLoved: lovedTrackIDs.contains(track.id))
        }
        self.closeState = closeState
        self.onClose = onClose
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    denseField("Title", text: $title, key: "title")

                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            denseLabel("Artist")
                            compactTextField(text: $artist, key: "artist", label: "Artist")
                                .frame(minWidth: 180)
                            denseLabel("Year", width: 52)
                            compactTextField(text: $year, key: "year", label: "Year")
                                .frame(width: 112)
                        }

                        GridRow {
                            denseLabel("Album")
                            compactTextField(text: $album, key: "album", label: "Album")
                            denseLabel("Track #", width: 52)
                            numberPair(
                                number: $trackNumber,
                                numberKey: "trackNumber",
                                numberLabel: "Track Number",
                                total: $trackTotal,
                                totalKey: "trackTotal",
                                totalLabel: "Track Total"
                            )
                                .frame(width: 112)
                        }

                        GridRow {
                            denseLabel("Album Artist")
                            compactTextField(text: $albumArtist, key: "albumArtist", label: "Album Artist")
                            denseLabel("Disc #", width: 52)
                            numberPair(
                                number: $discNumber,
                                numberKey: "discNumber",
                                numberLabel: "Disc Number",
                                total: $discTotal,
                                totalKey: "discTotal",
                                totalLabel: "Disc Total"
                            )
                                .frame(width: 112)
                        }

                        GridRow {
                            denseLabel("Composer")
                            compactTextField(text: $composer, key: "composer", label: "Composer")
                            denseLabel("BPM", width: 52)
                            HStack(spacing: 4) {
                                compactTextField(
                                    text: $beatsPerMinute,
                                    key: "beatsPerMinute",
                                    label: "Beats Per Minute"
                                )
                                Button {
                                    calculateBPM()
                                } label: {
                                    if isCalculatingBPM {
                                        ProgressView()
                                            .controlSize(.mini)
                                    } else {
                                        Text("Calculate")
                                            .font(.caption)
                                    }
                                }
                                .disabled(isCalculatingBPM || trackTargets.count != 1)
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .frame(width: 200)
                        }

                        GridRow {
                            denseLabel("Genre")
                            compactTextField(text: $genre, key: "genre", label: "Genre")
                            denseLabel("Favorite", width: 52)
                            favoriteEditor
                                .frame(width: 112)
                        }
                        GridRow {
                            denseLabel("Rating")
                            ratingEditor
                                .frame(minWidth: 180, alignment: .leading)
                            Color.clear.frame(width: 52, height: 1)
                            Color.clear.frame(width: 112, height: 1)
                        }
                    }

                    denseField("Comment", text: $comment, key: "comment")
                    technicalSummary
                        .padding(.leading, 88)
                    ForEach(validationErrors, id: \.self) { error in
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Artwork")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    artworkEditor
                        .frame(width: 160, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity)

            HStack {
                Spacer()
                Button("Cancel") { requestClose() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isSaving)
                Button(isSaving ? "Saving…" : "OK") { submitChanges() }
                .keyboardShortcut(.defaultAction)
                .disabled(canSave == false || isSaving)
            }
            if let artworkError {
                Text(artworkError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if let saveError {
                Text(saveError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(20)
        .frame(
            minWidth: 700,
            idealWidth: 760,
            maxWidth: .infinity,
            minHeight: 320,
            idealHeight: 340,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .onAppear {
            artworkTasks.activate()
            load()
        }
        .task {
            do {
                let scope = try await libraryActions.prepareTrackArtworkScope(trackIDs: trackTargets.map(\.id))
                try Task.checkCancellation()
                artworkScope = scope
            } catch is CancellationError {
                return
            } catch {
                artworkError = "Could not prepare album artwork: \(error.localizedDescription)"
            }
        }
        .onDisappear { artworkTasks.invalidate() }
        .onChange(of: editedFields) { _, fields in
            closeState.isDirty = !fields.isEmpty || artworkEdited
        }
        .onChange(of: artworkEdited) { _, edited in
            closeState.isDirty = edited || !editedFields.isEmpty
        }
        .alert("Discard Metadata Changes?", isPresented: $confirmsDiscard) {
            Button("Continue Editing", role: .cancel) {}
            Button("Discard", role: .destructive) { closeWindow() }
        } message: {
            Text("Your unsaved metadata, Favorite, Rating, or artwork changes will be lost.")
        }
        .sheet(isPresented: Binding(
            get: { !metadataConflicts.isEmpty },
            set: { if !$0 { metadataConflicts = [] } }
        )) {
            conflictSheet
        }
    }

    private func requestClose() {
        guard !isSaving else { return }
        if editedFields.isEmpty && !artworkEdited { closeWindow() }
        else { confirmsDiscard = true }
    }

    private var conflictSheet: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Metadata Changed Elsewhere").font(.title2.weight(.semibold))
                Text("Choose whether to keep the current library value or use the value from this editor. Keep Current is selected by default.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            Divider()
            List(metadataConflicts) { conflict in
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(targetTitle(conflict.trackID)) — \(fieldLabel(conflict.field))")
                        .font(.headline)
                    Text("Opening: \(conflict.opening.displayText)").font(.caption)
                    Text("Current: \(conflict.current.displayText)").font(.caption)
                    Text("Mine: \(conflict.proposed.displayText)").font(.caption)
                    Picker("Resolution", selection: Binding(
                        get: { conflictResolutions[conflict.id] ?? .useCurrent },
                        set: { conflictResolutions[conflict.id] = $0 }
                    )) {
                        Text("Keep Current").tag(TrackMetadataConflictResolution.useCurrent)
                        Text("Use Mine").tag(TrackMetadataConflictResolution.useProposed)
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.vertical, 5)
            }
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { metadataConflicts = [] }
                    .disabled(isSaving)
                Button("Apply Choices") {
                    let decisions = metadataConflicts.map { conflict in
                        TrackMetadataConflictDecision(
                            trackID: conflict.trackID,
                            field: conflict.field,
                            expectedCurrent: conflict.current,
                            resolution: conflictResolutions[conflict.id] ?? .useCurrent
                        )
                    }
                    submitChanges(decisions: decisions)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving)
            }
            .padding()
        }
        .frame(minWidth: 660, minHeight: 440)
    }

    private func closeWindow() {
        closeState.allowsClose = true
        closeState.isDirty = false
        onClose()
        dismiss()
    }

    // MARK: - Artwork (Songbird Track Editor style)

    private var artworkEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.quaternary)

                if artworkMixed && artworkData == nil && !artworkCleared {
                    VStack(spacing: 6) {
                        Image(systemName: "photo")
                            .font(.system(size: 22, weight: .light))
                        Text("Mixed")
                            .font(.caption)
                    }
                    .foregroundColor(secondaryColor)
                } else if let data = artworkData, !artworkCleared {
                    ArtworkThumbnailView(
                        reference: .embedded(id: artworkRevision, data: data),
                        pointSize: CGSize(width: 160, height: 160),
                        accessibilityLabel: "Album artwork",
                        cornerRadius: 6
                    )
                } else {
                    VStack(spacing: 4) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 20, weight: .light))
                        Text("Drag here")
                            .font(.caption2)
                    }
                    .foregroundColor(secondaryColor)
                }

                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.accentColor, lineWidth: 2)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.accentColor.opacity(0.12))
                        )
                }
            }
            .frame(width: 160, height: 160)
            .contentShape(Rectangle())
            .onTapGesture {
                pickArtworkFile()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(hasArtwork ? "Replace artwork" : "Add artwork") // [VERIFY] confirm label matches intent
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                pickArtworkFile()
            }
            .help(hasArtwork ? "Click to choose different artwork" : "Click to add artwork")
            .onDrop(of: [.image, .fileURL], isTargeted: $isDropTargeted) { providers in
                handleDrop(providers)
            }
            .contextMenu {
                if hasArtwork {
                    Button("Clear") { clearArtwork() }
                }
                Button(hasArtwork ? "Replace…" : "Add…") { pickArtworkFile() }
                Divider()
                Button("Find on Discogs…") { showDiscogsSearch() }
                    .disabled(relatedAlbumID == nil)
            }

            if hasArtwork || artworkCleared {
                HStack {
                    Spacer()
                    Button {
                        clearArtwork()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Clear artwork") // [VERIFY] confirm label matches intent
                    .help("Clear artwork")
                }
                .frame(width: 160)
                .controlSize(.small)
            }
            Text(artworkScope.map { "Artwork for all \($0.targets.count) album tracks" }
                ?? "Preparing album artwork…")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 160, alignment: .leading)
            if isMulti, relatedAlbumID == nil {
                Text("Discogs artwork is available only when all selected tracks belong to one album.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 160, alignment: .leading)
            }
        }
    }

    private func denseField(_ label: String, text: Binding<String>, key: String) -> some View {
        HStack(spacing: 12) {
            denseLabel(label)
            compactTextField(text: text, key: key, label: label)
        }
    }

    private func denseLabel(_ label: String, width: CGFloat = 76) -> some View {
        Text(label)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(width: width, alignment: .trailing)
    }

    private func compactTextField(
        text: Binding<String>,
        key: String,
        label: String
    ) -> some View {
        TextField(
            mixedFields.contains(key) ? "Mixed" : "",
            text: Binding(
                get: { text.wrappedValue },
                set: { value in
                    text.wrappedValue = value
                    editedFields.insert(key)
                }
            )
        )
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel(label)
    }

    private func numberPair(
        number: Binding<String>,
        numberKey: String,
        numberLabel: String,
        total: Binding<String>,
        totalKey: String,
        totalLabel: String
    ) -> some View {
        HStack(spacing: 4) {
            compactTextField(text: number, key: numberKey, label: numberLabel)
            Text("/")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            compactTextField(text: total, key: totalKey, label: totalLabel)
        }
    }

    private var favoriteEditor: some View {
        Button {
            isLoved.toggle()
            mixedFields.remove("favorite")
            editedFields.insert("favorite")
        } label: {
            Image(systemName: isLoved ? "heart.fill" : "heart")
                .foregroundStyle(isLoved ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(isLoved ? "Remove from Favorites" : "Add to Favorites")
    }

    private var ratingEditor: some View {
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { value in
                Button {
                    rating = rating == value ? 0 : value
                    mixedFields.remove("rating")
                    editedFields.insert("rating")
                } label: {
                    Image(systemName: value <= rating ? "star.fill" : "star")
                        .foregroundStyle(value <= rating ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help("Rate \(value) of 5")
            }
        }
    }

    private var technicalSummary: some View {
        Group {
            if isMulti {
                Text("\(trackTargets.count) selected tracks")
            } else if let track = trackTargets.first {
                Text([
                    track.fileKind.isEmpty ? nil : track.fileKind,
                    track.bitrate > 0 ? "\(track.bitrate) kbps" : nil,
                    track.sampleRate > 0 ? "\(track.sampleRate.formatted()) Hz" : nil
                ].compactMap { $0 }.joined(separator: "  •  "))
            }
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
        .lineLimit(1)
    }

    private func load() {
        guard let first = trackTargets.first else { return }
        editedFields.removeAll()
        title = first.title
        artist = first.artist
        album = first.album
        albumArtist = first.albumArtist
        genre = first.genre
        composer = first.composer
        comment = first.comment
        year = first.year == 0 ? "" : "\(first.year)"
        trackNumber = first.trackNumber == 0 ? "" : "\(first.trackNumber)"
        trackTotal = first.trackTotal == 0 ? "" : "\(first.trackTotal)"
        discNumber = first.discNumber == 0 ? "" : "\(first.discNumber)"
        discTotal = first.discTotal == 0 ? "" : "\(first.discTotal)"
        beatsPerMinute = first.beatsPerMinute == 0 ? "" : "\(first.beatsPerMinute)"
        rating = first.rating
        isLoved = first.isLoved
        artworkData = first.artworkData
        artworkRevision = UUID()
        artworkCleared = false
        artworkEdited = false
        artworkMixed = false

        guard isMulti else { return }
        if trackTargets.contains(where: { $0.title != first.title }) { mixedFields.insert("title"); title = "" }
        if trackTargets.contains(where: { $0.artist != first.artist }) { mixedFields.insert("artist"); artist = "" }
        if trackTargets.contains(where: { $0.album != first.album }) { mixedFields.insert("album"); album = "" }
        if trackTargets.contains(where: { $0.albumArtist != first.albumArtist }) { mixedFields.insert("albumArtist"); albumArtist = "" }
        if trackTargets.contains(where: { $0.genre != first.genre }) { mixedFields.insert("genre"); genre = "" }
        if trackTargets.contains(where: { $0.composer != first.composer }) { mixedFields.insert("composer"); composer = "" }
        if trackTargets.contains(where: { $0.comment != first.comment }) { mixedFields.insert("comment"); comment = "" }
        if trackTargets.contains(where: { $0.year != first.year }) { mixedFields.insert("year"); year = "" }
        if trackTargets.contains(where: { $0.trackNumber != first.trackNumber }) { mixedFields.insert("trackNumber"); trackNumber = "" }
        if trackTargets.contains(where: { $0.trackTotal != first.trackTotal }) { mixedFields.insert("trackTotal"); trackTotal = "" }
        if trackTargets.contains(where: { $0.discNumber != first.discNumber }) { mixedFields.insert("discNumber"); discNumber = "" }
        if trackTargets.contains(where: { $0.discTotal != first.discTotal }) { mixedFields.insert("discTotal"); discTotal = "" }
        if trackTargets.contains(where: { $0.beatsPerMinute != first.beatsPerMinute }) {
            mixedFields.insert("beatsPerMinute")
            beatsPerMinute = ""
        }
        if trackTargets.contains(where: { $0.rating != first.rating }) {
            mixedFields.insert("rating")
            rating = 0
        }
        if trackTargets.contains(where: { $0.isLoved != first.isLoved }) {
            mixedFields.insert("favorite")
            isLoved = false
        }

        let arts = trackTargets.map(\.artworkData)
        if arts.contains(where: { $0 != first.artworkData }) {
            artworkMixed = true
            artworkData = nil
        }
    }

    private func clearArtwork() {
        artworkData = nil
        artworkCleared = true
        artworkEdited = true
        artworkRevision = UUID()
        artworkMixed = false
    }

    private func setArtwork(_ data: Data) {
        artworkData = data
        artworkCleared = false
        artworkEdited = true
        artworkRevision = UUID()
        artworkMixed = false
        artworkError = nil
    }

    private func pickArtworkFile() {
        guard let artworkLease = artworkTasks.lease() else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.jpeg, .png, .gif, .bmp, .webP, .tiff, .heic]
        panel.message = "Select Artwork File"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            loadArtwork(from: url, lease: artworkLease)
        }
    }

    private func loadArtwork(from url: URL, lease: ViewTaskSlot.Lease) {
        artworkTasks.start(lease: lease) {
            do {
                let data = try await artworkLoader.load(from: url)
                try Task.checkCancellation()
                setArtwork(data)
            } catch is CancellationError {
                return
            } catch {
                artworkError = error.localizedDescription
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let artworkLease = artworkTasks.lease() else { return false }
        if let imageProvider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }) {
            imageProvider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                guard let data else { return }
                Task { @MainActor in
                    artworkTasks.start(lease: artworkLease) {
                        do {
                            setArtwork(try await artworkLoader.validate(data))
                        } catch is CancellationError {
                            return
                        } catch {
                            artworkError = error.localizedDescription
                        }
                    }
                }
            }
            return true
        }
        if let fileProvider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) {
            fileProvider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let u = item as? URL {
                    url = u
                } else {
                    url = nil
                }
                guard let url else { return }
                Task { @MainActor in
                    loadArtwork(from: url, lease: artworkLease)
                }
            }
            return true
        }
        return false
    }

    private func numericError(
        _ text: String,
        label: String,
        range: ClosedRange<Int>
    ) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        guard let value = Int(trimmed), range.contains(value) else {
            return "\(label) must be a whole number between \(range.lowerBound) and \(range.upperBound)."
        }
        return nil
    }

    private func submitChanges(
        decisions: [TrackMetadataConflictDecision] = []
    ) {
        guard canSave, !isSaving else { return }
        let changeSet = metadataChangeSet()
        guard !changeSet.edits.isEmpty else {
            closeWindow()
            return
        }
        isSaving = true
        closeState.isSaving = true
        saveError = nil
        Task { @MainActor in
            defer {
                isSaving = false
                closeState.isSaving = false
            }
            do {
                switch try await libraryActions.applyTrackMetadata(changeSet, decisions: decisions) {
                case .saved:
                    metadataConflicts = []
                    closeWindow()
                case .conflicts(let conflicts):
                    metadataConflicts = conflicts
                    conflictResolutions = Dictionary(uniqueKeysWithValues: conflicts.map {
                        ($0.id, .useCurrent)
                    })
                }
            } catch {
                saveError = "Could not save track information: \(error.localizedDescription)"
            }
        }
    }

    private func metadataChangeSet() -> TrackMetadataChangeSet {
        var edits: [TrackMetadataField: TrackMetadataValue] = [:]
        func text(_ key: String, _ field: TrackMetadataField, _ value: String) {
            if editedFields.contains(key) { edits[field] = .text(value) }
        }
        func number(_ key: String, _ field: TrackMetadataField, _ value: String) {
            if editedFields.contains(key) {
                edits[field] = .number(Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0)
            }
        }
        text("title", .title, title)
        text("artist", .artist, artist)
        text("album", .album, album)
        text("albumArtist", .albumArtist, albumArtist)
        text("genre", .genre, GenreMetadata.normalized(genre))
        text("composer", .composer, composer)
        text("comment", .comment, comment)
        number("year", .year, year)
        number("trackNumber", .trackNumber, trackNumber)
        number("trackTotal", .trackTotal, trackTotal)
        number("discNumber", .discNumber, discNumber)
        number("discTotal", .discTotal, discTotal)
        number("beatsPerMinute", .beatsPerMinute, beatsPerMinute)
        if editedFields.contains("rating") { edits[.rating] = .number(rating) }
        if editedFields.contains("favorite") { edits[.favorite] = .flag(isLoved) }
        if artworkEdited {
            edits[.artwork] = .artwork(artworkCleared ? nil : artworkData)
        }
        return TrackMetadataChangeSet(
            baselines: trackTargets.map {
                TrackMetadataBaseline(trackID: $0.id, values: metadataValues(target: $0))
            },
            edits: edits,
            artworkScope: artworkScope
        )
    }

    private func metadataValues(target: TrackInfoTarget) -> [TrackMetadataField: TrackMetadataValue] {
        [
            .title: .text(target.title), .artist: .text(target.artist),
            .album: .text(target.album), .albumArtist: .text(target.albumArtist),
            .genre: .text(GenreMetadata.normalized(target.genre)),
            .composer: .text(target.composer), .comment: .text(target.comment),
            .year: .number(target.year), .trackNumber: .number(target.trackNumber),
            .trackTotal: .number(target.trackTotal), .discNumber: .number(target.discNumber),
            .discTotal: .number(target.discTotal), .beatsPerMinute: .number(target.beatsPerMinute),
            .rating: .number(target.rating), .favorite: .flag(target.isLoved),
            .artwork: .artwork(target.artworkData),
        ]
    }

    private func targetTitle(_ id: UUID) -> String {
        trackTargets.first(where: { $0.id == id })?.title
            ?? artworkScope?.targets.first(where: { $0.trackID == id })?.title
            ?? id.uuidString
    }

    private func fieldLabel(_ field: TrackMetadataField) -> String {
        switch field {
        case .albumArtist: "Album Artist"
        case .trackNumber: "Track Number"
        case .trackTotal: "Track Total"
        case .discNumber: "Disc Number"
        case .discTotal: "Disc Total"
        case .beatsPerMinute: "BPM"
        default: field.rawValue.capitalized
        }
    }

    private func showDiscogsSearch() {
        guard let relatedAlbumID,
              let artworkLease = artworkTasks.lease() else { return }
        do {
            let targetID = relatedAlbumID
            var descriptor = FetchDescriptor<Album>(
                predicate: #Predicate { album in album.id == targetID }
            )
            descriptor.fetchLimit = 1
            guard let album = try modelContext.fetch(descriptor).first else {
                artworkError = "This album is no longer in the library."
                return
            }
            let albumTarget = DiscogsArtworkAlbumTarget(album: album)
            libraryActions.searchForArtwork(
                albumIDs: [album.id],
                title: album.title,
                completion: {
                    artworkTasks.start(lease: artworkLease) {
                        do {
                            guard let currentAlbum = try albumTarget.resolve(in: modelContext) else {
                                artworkError = "This album is no longer in the library."
                                return
                            }
                            if let data = currentAlbum.artworkData {
                                artworkData = data
                                artworkCleared = false
                                artworkEdited = false
                                artworkRevision = UUID()
                            }
                        } catch {
                            artworkError = "Could not reload artwork: \(error.localizedDescription)"
                        }
                    }
                }
            )
        } catch {
            artworkError = "Could not find the current album: \(error.localizedDescription)"
        }
    }

    private func calculateBPM() {
        guard trackTargets.count == 1, let target = trackTargets.first else { return }
        guard !isCalculatingBPM else { return }
        isCalculatingBPM = true
        let context = modelContext
        Task {
            do {
                let tracks = try TrackInfoTarget.resolve([target], in: context)
                guard let track = tracks.first else {
                    isCalculatingBPM = false
                    return
                }
                let url = URL(fileURLWithPath: track.path)
                let bpm = await MetadataReader.detectBPM(from: url)
                try Task.checkCancellation()
                if bpm > 0 {
                    beatsPerMinute = "\(bpm)"
                    editedFields.insert("beatsPerMinute")
                    mixedFields.remove("beatsPerMinute")
                }
            } catch {}
            isCalculatingBPM = false
        }
    }
}

/// Presents Edit Metadata as a movable, resizable macOS window instead of an
/// attached sheet. Each invocation may remain open for side-by-side editing.
@MainActor
enum TrackInfoWindowPresenter {
    private static var coordinators: [String: TrackInfoWindowCoordinator] = [:]

    static func show(
        tracks: [Track],
        actions: LibraryItemActionHandler,
        snapshots: LibrarySnapshotStore
    ) {
        guard !tracks.isEmpty else { return }
        let key = tracks.map(\.id.uuidString).sorted().joined(separator: "|")
        if let existing = coordinators[key]?.window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let coordinator = TrackInfoWindowCoordinator()
        let closeState = TrackInfoCloseState()
        let title = tracks.count == 1 ? "Edit Metadata — \(tracks[0].title)" : "Edit Metadata"
        let rootView = TrackInfoView(
            tracks: tracks,
            lovedTrackIDs: Set(tracks.filter {
                snapshots.trackSnapshot(id: $0.id)?.isLoved == true
            }.map(\.id)),
            closeState: closeState,
            onClose: { [weak coordinator] in coordinator?.window?.close() }
        )
        .modelContainer(MediaLibrary.shared.container)
        .environmentObject(actions)

        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 760, height: 340))
        window.contentMinSize = NSSize(width: 700, height: 320)
        window.isReleasedWhenClosed = false
        window.center()

        coordinator.window = window
        coordinator.closeState = closeState
        coordinator.onClose = {
            coordinators.removeValue(forKey: key)
        }
        window.delegate = coordinator
        coordinators[key] = coordinator

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
private final class TrackInfoWindowCoordinator: NSObject, NSWindowDelegate {
    weak var window: NSWindow?
    var closeState: TrackInfoCloseState?
    var onClose: (() -> Void)?

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if closeState?.isSaving == true { return false }
        guard let closeState, closeState.isDirty, !closeState.allowsClose else { return true }
        let alert = NSAlert()
        alert.messageText = "Discard Metadata Changes?"
        alert.informativeText = "Your unsaved metadata, Favorite, Rating, or artwork changes will be lost."
        alert.addButton(withTitle: "Continue Editing")
        alert.addButton(withTitle: "Discard")
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            closeState.allowsClose = true
            return true
        }
        return false
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}
