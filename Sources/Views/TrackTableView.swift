import SwiftUI
import SwiftData
import AppKit

private enum TrackTableCoordinateSpace {
    static let columnHeader = "songbird.track-column-header"
}

private struct ColumnHeaderFramePreferenceKey: PreferenceKey {
    static let defaultValue: [TrackSortColumn: CGRect] = [:]

    static func reduce(
        value: inout [TrackSortColumn: CGRect],
        nextValue: () -> [TrackSortColumn: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

/// Keeps SwiftUI's themed row background as the only selection paint layer.
@MainActor
enum TrackTableNativeSelectionAppearance {
    static func apply(to tableView: NSTableView) {
        tableView.selectionHighlightStyle = .none
        tableView.allowsMultipleSelection = true
    }
}

@MainActor
enum TrackTableDoubleClickScope {
    static func owns(
        hitTable: NSTableView,
        monitoredTable: NSTableView?,
        eventIsInsideMonitor: Bool
    ) -> Bool {
        guard eventIsInsideMonitor else { return false }
        guard let monitoredTable else { return true }
        return hitTable === monitoredTable
    }

    static func accepts(nearestControl: NSControl?, tableView: NSTableView) -> Bool {
        nearestControl == nil || nearestControl === tableView
    }
}

/// Bridges native table appearance and double-clicks without participating in
/// hit testing, leaving selection and modifier-key behavior to the macOS List.
struct TrackTableDoubleClickMonitor: NSViewRepresentable {
    let action: (Int) -> Void
    var selectionAction: ((Int, NSEvent.ModifierFlags) -> Void)?
    var selectAllAction: (() -> Void)?

    func makeNSView(context: Context) -> MonitoringView {
        let view = MonitoringView()
        view.action = action
        view.selectionAction = selectionAction
        view.selectAllAction = selectAllAction
        return view
    }

    func updateNSView(_ nsView: MonitoringView, context: Context) {
        nsView.action = action
        nsView.selectionAction = selectionAction
        nsView.selectAllAction = selectAllAction
        nsView.updateNativeSelectionAppearance()
    }

    final class MonitoringView: NSView {
        var action: ((Int) -> Void)?
        var selectionAction: ((Int, NSEvent.ModifierFlags) -> Void)?
        var selectAllAction: (() -> Void)?
        private var eventMonitor: Any?
        private var keyEventMonitor: Any?
        private weak var monitoredTableView: NSTableView?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            updateEventMonitor()
            updateNativeSelectionAppearance()
        }

        override func layout() {
            super.layout()
            updateNativeSelectionAppearance()
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }

        private func updateEventMonitor() {
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
                self.eventMonitor = nil
            }
            if let keyEventMonitor {
                NSEvent.removeMonitor(keyEventMonitor)
                self.keyEventMonitor = nil
            }
            guard window != nil else { return }
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) {
                [weak self] event in
                guard let self,
                      event.window === self.window,
                      event.clickCount == 1 || event.clickCount == 2 else {
                    return event
                }
                let pointInMonitor = self.convert(event.locationInWindow, from: nil)
                let eventIsInsideMonitor = self.bounds.contains(pointInMonitor)
                guard let hitView = event.window?.contentView?.hitTest(event.locationInWindow),
                      hitView.enclosingScrollView?.verticalScroller !== hitView,
                      hitView.enclosingScrollView?.horizontalScroller !== hitView,
                      let rowView = hitView.ancestor(of: NSTableRowView.self),
                      let tableView = rowView.ancestor(of: NSTableView.self),
                      TrackTableDoubleClickScope.owns(
                        hitTable: tableView,
                        monitoredTable: self.monitoredTableView,
                        eventIsInsideMonitor: eventIsInsideMonitor
                      ) else {
                    return event
                }
                guard TrackTableDoubleClickScope.accepts(
                    nearestControl: hitView.ancestor(of: NSControl.self),
                    tableView: tableView
                ) else {
                    return event
                }
                let pointInRow = rowView.convert(event.locationInWindow, from: nil)
                guard rowView.bounds.contains(pointInRow) else { return event }
                let pointInTable = tableView.convert(event.locationInWindow, from: nil)
                let row = tableView.row(at: pointInTable)
                guard row >= 0 else { return event }
                if self.monitoredTableView == nil {
                    self.monitoredTableView = tableView
                    TrackTableNativeSelectionAppearance.apply(to: tableView)
                }
                // Do not mutate SwiftUI state while AppKit is still dispatching
                // the mouse-down event. Doing so creates an AttributeGraph cycle
                // in the live List and can temporarily remove its window from the
                // on-screen window list. Preserve the native event, then perform
                // the bridged action on the next main-actor turn.
                let modifiers = event.modifierFlags
                let activation = self.action
                let selection = self.selectionAction
                Task { @MainActor in
                    if event.clickCount == 2 {
                        activation?(row)
                    } else {
                        selection?(row, modifiers)
                    }
                }
                return event
            }
            keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
                [weak self] event in
                guard let self,
                      event.window === self.window,
                      event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                      event.charactersIgnoringModifiers?.lowercased() == "a",
                      self.window?.firstResponder is NSTextView == false else {
                    return event
                }
                let selectAll = self.selectAllAction
                Task { @MainActor in selectAll?() }
                return nil
            }
        }

        func updateNativeSelectionAppearance() {
            guard let window, bounds.isEmpty == false else {
                monitoredTableView = nil
                return
            }
            let point = convert(NSPoint(x: bounds.midX, y: bounds.midY), to: nil)
            guard let hitView = window.contentView?.hitTest(point),
                  let tableView = hitView.ancestor(of: NSTableView.self) else {
                monitoredTableView = nil
                return
            }
            monitoredTableView = tableView
            TrackTableNativeSelectionAppearance.apply(to: tableView)
        }

        isolated deinit {
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
            }
            if let keyEventMonitor {
                NSEvent.removeMonitor(keyEventMonitor)
            }
        }
    }
}

private extension NSView {
    func ancestor<T: NSView>(of type: T.Type) -> T? {
        var candidate: NSView? = self
        while let view = candidate {
            if let match = view as? T { return match }
            candidate = view.superview
        }
        return nil
    }
}

@MainActor
private final class TrackDisplayCache {
    struct Key: Equatable {
        let trackRevision: Int
        let searchText: String
        let selectedArtist: String?
        let selectedAlbum: String?
        let selectedGenre: String?
        let sortColumnRaw: String
        let sortAscending: Bool
        let usePlaylistOrder: Bool
    }

    private var key: Key?
    private var tracks: [Track] = []

    func resolve(for key: Key, build: () -> [Track]) -> [Track] {
        guard self.key != key else { return tracks }
        let resolved = build()
        self.key = key
        tracks = resolved
        return resolved
    }
}

public enum TrackSortColumn: String, CaseIterable, Identifiable, Sendable {
    case title, album, albumArtist, albumRating, artist, beatsPerMinute
    case bitRate, comments, composer
    case dateAdded, dateModified, description, discNumber, rating
    case genre, grouping, kind, lastPlayed, lastSkipped, movementName
    case movementNumber, playCount, starRating, releaseDate
    case sampleRate, size, skipCount, sortAlbum, sortAlbumArtist, sortArtist
    case sortComposer, sortTitle, duration, trackNumber, work, year

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .album: return "Album"
        case .albumArtist: return "Album Artist"
        case .albumRating: return "Album Rating"
        case .artist: return "Artist"
        case .beatsPerMinute: return "BPM"
        case .bitRate: return "Bit Rate"
        case .comments: return "Comments"
        case .composer: return "Composer"
        case .dateAdded: return "Date Added"
        case .dateModified: return "Date Modified"
        case .description: return "Description"
        case .discNumber: return "Disc Number"
        case .rating: return "Favorite"
        case .genre: return "Genre"
        case .grouping: return "Grouping"
        case .kind: return "Kind"
        case .lastPlayed: return "Last Played"
        case .lastSkipped: return "Last Skipped"
        case .movementName: return "Movement Name"
        case .movementNumber: return "Movement Number"
        case .playCount: return "Plays"
        case .starRating: return "Rating"
        case .releaseDate: return "Release Date"
        case .sampleRate: return "Sample Rate"
        case .size: return "Size"
        case .skipCount: return "Skips"
        case .sortAlbum: return "Sort Album"
        case .sortAlbumArtist: return "Sort Album Artist"
        case .sortArtist: return "Sort Artist"
        case .sortComposer: return "Sort Composer"
        case .sortTitle: return "Sort Title"
        case .duration: return "Time"
        case .title: return "Title"
        case .trackNumber: return "Track"
        case .work: return "Work"
        case .year: return "Year"
        }
    }

    public var isSupported: Bool {
        switch self {
        case .rating, .albumArtist, .title, .album, .duration, .genre, .playCount,
             .artist, .albumRating, .beatsPerMinute, .bitRate, .comments, .composer,
             .dateAdded, .dateModified, .discNumber, .kind, .lastPlayed, .starRating,
             .sampleRate, .size, .trackNumber, .year:
            true
        default:
            false
        }
    }

    public static var supportedCases: [TrackSortColumn] {
        allCases.filter(\.isSupported)
    }

    var sortsAscendingByDefault: Bool {
        switch self {
        case .album, .albumArtist, .artist,
             .comments, .composer, .description, .genre, .grouping, .kind,
             .movementName, .sortAlbum, .sortAlbumArtist, .sortArtist, .sortComposer,
             .sortTitle, .title, .work:
            return true
        default:
            return false
        }
    }

    var isRightAligned: Bool {
        switch self {
        case .albumRating, .beatsPerMinute, .bitRate, .discNumber, .duration,
             .movementNumber, .playCount, .sampleRate, .size, .skipCount,
             .starRating, .year:
            return true
        default:
            return false
        }
    }
}

/// Keeps high-frequency pointer state local to the header so dragging a column
/// does not invalidate the track list beneath it on every mouse movement.
struct TrackTableColumnHeader: View {
    @Binding var columnPrefsRaw: String
    @Binding var sortColumnRaw: String
    @Binding var sortAscending: Bool
    @Binding var usePlaylistOrder: Bool
    @Binding var resizePreviewWidths: [TrackSortColumn: CGFloat]
    let showsPlaylistOrderOption: Bool
    var presentation: TrackTablePresentation = .comfortable

    @Environment(\.colorScheme) private var colorScheme
    @State private var resizeStartWidth: CGFloat?
    @State private var resizingColumn: TrackSortColumn?
    @State private var draggingColumn: TrackSortColumn?
    @State private var targetedColumn: TrackSortColumn?
    @State private var placesDraggedColumnAfterTarget = false
    @State private var columnFrames: [TrackSortColumn: CGRect] = [:]

    private var secondaryColor: Color {
        SongbirdTheme.secondaryText(for: colorScheme)
    }

    private var columnPrefs: [TrackColumnPref] {
        TrackTableColumnPrefs.decode(columnPrefsRaw)
    }

    private var visibleColumns: [(pref: TrackColumnPref, column: TrackSortColumn)] {
        columnPrefs.compactMap { pref in
            guard pref.visible, let column = pref.column, column.isSupported else { return nil }
            return (pref, column)
        }
    }

    private var sortColumn: TrackSortColumn {
        TrackSortColumn(rawValue: sortColumnRaw) ?? .dateAdded
    }

    var body: some View {
        HStack(spacing: 0) {
            if presentation.showsArtwork {
                Color.clear.frame(width: presentation.artworkGutterWidth)
            }
            ForEach(Array(visibleColumns.enumerated()), id: \.element.column) { index, item in
                let width = resizePreviewWidths[item.column]
                    ?? TrackTableColumnPrefs.resolvedWidth(for: item.pref)
                draggableColumnHeader(
                    item.column,
                    width: width
                )
                if index < visibleColumns.count - 1 {
                    ColumnSeparator(
                        resizable: item.column != .rating && item.column != .duration && item.column != .playCount && item.column != .kind && item.column != .beatsPerMinute,
                        onEnd: { delta in
                            let start = resizeStartWidth
                                ?? resizePreviewWidths[item.column]
                                ?? width
                            let finalWidth = TrackTableColumnPrefs.clampedWidth(start + delta, for: item.column)
                            setColumnWidth(item.column, to: finalWidth)
                            resizePreviewWidths[item.column] = nil
                            resizingColumn = nil
                            resizeStartWidth = nil
                        }
                    )
                    .frame(width: 8)
                    .frame(maxHeight: .infinity)
                }
            }
        }
        .font(.caption.bold())
        .foregroundColor(secondaryColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 0)
        .frame(height: presentation.headerHeight)
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .background(SongbirdTheme.nowPlayingBar(for: colorScheme))
        .coordinateSpace(name: TrackTableCoordinateSpace.columnHeader)
        .onPreferenceChange(ColumnHeaderFramePreferenceKey.self) { frames in
            guard columnFrames != frames else { return }
            columnFrames = frames
        }
    }

    private func draggableColumnHeader(
        _ column: TrackSortColumn,
        width: CGFloat
    ) -> some View {
        columnHeaderLabel(column, width: width)
            .contentShape(Rectangle())
            .simultaneousGesture(columnReorderGesture(for: column))
            .onTapGesture {
                sortByColumn(column)
            }
            .focusable()
            .onKeyPress(keys: [.return, .space]) { _ in
                sortByColumn(column)
                return .handled
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Sorts tracks. Drag to reorder this column.")
            .accessibilityAction {
                sortByColumn(column)
            }
            .accessibilityActions {
                if canMoveColumn(column, direction: -1) {
                    Button("Move Left") { moveColumn(column, direction: -1) }
                }
                if canMoveColumn(column, direction: 1) {
                    Button("Move Right") { moveColumn(column, direction: 1) }
                }
                Button("Narrow Column") { adjustColumnWidth(column, by: -16) }
                Button("Widen Column") { adjustColumnWidth(column, by: 16) }
            }
            .contextMenu {
                Button("Move Left") { moveColumn(column, direction: -1) }
                    .disabled(!canMoveColumn(column, direction: -1))
                Button("Move Right") { moveColumn(column, direction: 1) }
                    .disabled(!canMoveColumn(column, direction: 1))
                if showsPlaylistOrderOption {
                    Divider()
                    Button("Playlist Order") { usePlaylistOrder = true }
                }
                Divider()
                columnVisibilitySubmenu
                Divider()
                Button("Reset Columns") {
                    columnPrefsRaw = TrackTableColumnPrefs.encode(TrackTableColumnPrefs.defaults)
                }
            }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ColumnHeaderFramePreferenceKey.self,
                    value: [
                        column: proxy.frame(in: .named(TrackTableCoordinateSpace.columnHeader)),
                    ]
                )
            }
        }
        .overlay(
            alignment: placesDraggedColumnAfterTarget ? .trailing : .leading
        ) {
            if targetedColumn == column {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 2)
                    .accessibilityHidden(true)
            }
        }
        .opacity(draggingColumn == column ? 0.6 : 1)
        .help("Drag to reorder the \(column.label) column")
    }

    private func columnReorderGesture(for column: TrackSortColumn) -> some Gesture {
        DragGesture(
            minimumDistance: 4,
            coordinateSpace: .named(TrackTableCoordinateSpace.columnHeader)
        )
        .onChanged { value in
            guard resizingColumn == nil else { return }
            if draggingColumn != column {
                draggingColumn = column
            }
            guard let target = columnDropTarget(at: value.location), target.column != column else {
                if targetedColumn != nil {
                    targetedColumn = nil
                }
                return
            }
            if targetedColumn != target.column {
                targetedColumn = target.column
            }
            if placesDraggedColumnAfterTarget != target.placeAfter {
                placesDraggedColumnAfterTarget = target.placeAfter
            }
        }
        .onEnded { _ in
            defer { resetColumnDrag() }
            guard let draggingColumn, let targetedColumn else { return }
            moveColumn(
                draggingColumn,
                relativeTo: targetedColumn,
                placeAfter: placesDraggedColumnAfterTarget
            )
        }
    }

    private func columnDropTarget(
        at location: CGPoint
    ) -> (column: TrackSortColumn, placeAfter: Bool)? {
        let ordered = visibleColumns.compactMap { item -> (TrackSortColumn, CGRect)? in
            guard let frame = columnFrames[item.column] else { return nil }
            return (item.column, frame)
        }
        guard !ordered.isEmpty else { return nil }
        let target = ordered.min { lhs, rhs in
            horizontalDistance(from: location.x, to: lhs.1)
                < horizontalDistance(from: location.x, to: rhs.1)
        }
        guard let target else { return nil }
        return (target.0, location.x >= target.1.midX)
    }

    private func horizontalDistance(from x: CGFloat, to frame: CGRect) -> CGFloat {
        if x < frame.minX { return frame.minX - x }
        if x > frame.maxX { return x - frame.maxX }
        return 0
    }

    private func resetColumnDrag() {
        draggingColumn = nil
        targetedColumn = nil
        placesDraggedColumnAfterTarget = false
    }

    private func columnHeaderLabel(
        _ column: TrackSortColumn,
        width: CGFloat
    ) -> some View {
        let alignment: Alignment = column == .rating ? .center : .leading
        return HStack(spacing: 2) {
            Text(column.label)
            if !usePlaylistOrder || showsPlaylistOrderOption == false, sortColumn == column {
                Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
        }
        .frame(width: width, alignment: alignment)
    }

    private func sortByColumn(_ column: TrackSortColumn) {
        if showsPlaylistOrderOption {
            usePlaylistOrder = false
        }
        if sortColumn == column {
            sortAscending.toggle()
        } else {
            sortColumnRaw = column.rawValue
            sortAscending = column.sortsAscendingByDefault
        }
    }

    private func moveColumn(_ column: TrackSortColumn, direction: Int) {
        var prefs = columnPrefs
        TrackTableColumnPrefs.move(&prefs, id: column.rawValue, direction: direction)
        columnPrefsRaw = TrackTableColumnPrefs.encode(prefs)
    }

    private func moveColumn(
        _ column: TrackSortColumn,
        relativeTo target: TrackSortColumn,
        placeAfter: Bool
    ) {
        var prefs = columnPrefs
        TrackTableColumnPrefs.reorder(
            &prefs,
            movingID: column.rawValue,
            relativeTo: target.rawValue,
            placeAfter: placeAfter
        )
        columnPrefsRaw = TrackTableColumnPrefs.encode(prefs)
    }

    private func canMoveColumn(_ column: TrackSortColumn, direction: Int) -> Bool {
        guard let index = columnPrefs.firstIndex(where: { $0.id == column.rawValue }) else {
            return false
        }
        return columnPrefs.indices.contains(index + direction)
    }

    private func setColumnWidth(_ column: TrackSortColumn, to width: CGFloat) {
        var prefs = columnPrefs
        TrackTableColumnPrefs.setWidth(&prefs, id: column.rawValue, width: width)
        columnPrefsRaw = TrackTableColumnPrefs.encode(prefs)
    }

    private func adjustColumnWidth(_ column: TrackSortColumn, by delta: CGFloat) {
        guard let pref = columnPrefs.first(where: { $0.id == column.rawValue }) else { return }
        setColumnWidth(
            column,
            to: TrackTableColumnPrefs.resolvedWidth(for: pref) + delta
        )
    }

    private var columnVisibilitySubmenu: some View {
        Menu("Columns") {
            ForEach(columnPrefs.sorted {
                ($0.column?.label ?? $0.id).localizedCaseInsensitiveCompare($1.column?.label ?? $1.id)
                    == .orderedAscending
            }) { preference in
                    if let column = preference.column, column.isSupported {
                    Toggle(
                        column.label,
                        isOn: Binding(
                            get: { column == .title || preference.visible },
                            set: { isVisible in
                                setColumnVisibility(column, isVisible: isVisible)
                            }
                        )
                    )
                    .disabled(column == .title)
                }
            }
            Divider()
            Button("Reset Columns") {
                columnPrefsRaw = TrackTableColumnPrefs.encode(TrackTableColumnPrefs.defaults)
            }
        }
    }

    private func setColumnVisibility(
        _ column: TrackSortColumn,
        isVisible: Bool
    ) {
        guard column != .title else { return }
        var prefs = columnPrefs
        guard let index = prefs.firstIndex(where: { $0.id == column.rawValue }) else { return }
        prefs[index].visible = isVisible
        if let titleIndex = prefs.firstIndex(where: { $0.id == TrackSortColumn.title.rawValue }) {
            prefs[titleIndex].visible = true
        }
        columnPrefsRaw = TrackTableColumnPrefs.encode(prefs)
    }
}

/// Column separator that is either resizable or static.
private struct ColumnSeparator: View {
    let resizable: Bool
    var onEnd: (CGFloat) -> Void

    var body: some View {
        if resizable {
            ColumnResizeGrip(onEnd: onEnd)
        } else {
            ColumnStaticDivider()
        }
    }
}

/// Non-resizable vertical divider line matching the resize grip's visual style.
private struct ColumnStaticDivider: NSViewRepresentable {
    func makeNSView(context: Context) -> ColumnStaticDividerNSView {
        ColumnStaticDividerNSView()
    }

    func updateNSView(_ nsView: ColumnStaticDividerNSView, context: Context) {}
}

private class ColumnStaticDividerNSView: NSView {
    override var acceptsFirstResponder: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.separatorColor.withAlphaComponent(0.6).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1
        path.move(to: NSPoint(x: bounds.midX, y: 2))
        path.line(to: NSPoint(x: bounds.midX, y: bounds.height - 2))
        path.stroke()
    }
}

/// AppKit-backed resize grip that bypasses SwiftUI's gesture system.
/// Renders its own divider line and handles mouse events directly.
/// Only updates the column width on drag end to avoid re-render stuttering.
private struct ColumnResizeGrip: NSViewRepresentable {
    var onEnd: (CGFloat) -> Void

    func makeNSView(context: Context) -> ColumnResizeGripNSView {
        let view = ColumnResizeGripNSView()
        view.onEnd = onEnd
        return view
    }

    func updateNSView(_ nsView: ColumnResizeGripNSView, context: Context) {
        nsView.onEnd = onEnd
    }
}

private class ColumnResizeGripNSView: NSView {
    var onEnd: ((CGFloat) -> Void)?

    private var startLocationX: CGFloat = 0
    private var isDragging = false

    override init(frame: NSRect) {
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.separatorColor.withAlphaComponent(0.6).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1
        path.move(to: NSPoint(x: bounds.midX, y: 2))
        path.line(to: NSPoint(x: bounds.midX, y: bounds.height - 2))
        path.stroke()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.resizeLeftRight.push()
    }

    override func mouseExited(with event: NSEvent) {
        if !isDragging {
            NSCursor.pop()
        }
    }

    override func mouseDown(with event: NSEvent) {
        startLocationX = convert(event.locationInWindow, from: nil).x
        isDragging = true
    }

    override func mouseDragged(with event: NSEvent) {
        // No-op: width updates happen on mouseUp to avoid re-render stuttering.
    }

    override func mouseUp(with event: NSEvent) {
        let locationX = convert(event.locationInWindow, from: nil).x
        let delta = locationX - startLocationX
        isDragging = false
        NSCursor.pop()
        onEnd?(delta)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }
}

/// Multi-column track table with search, cascade filters, and play actions.
