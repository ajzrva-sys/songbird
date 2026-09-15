import Foundation

enum TrackTableLayout {
    static let horizontalInsets: CGFloat = 16
    static let columnGap: CGFloat = 8

    static func contentWidth(
        columns: [TrackTableColumnDefinition],
        presentation: TrackTablePresentation,
        previewWidths: [TrackSortColumn: CGFloat] = [:]
    ) -> CGFloat {
        let columnWidth = columns.reduce(CGFloat.zero) { total, definition in
            total + (previewWidths[definition.column] ?? CGFloat(definition.width))
        }
        let gaps = CGFloat(max(0, columns.count - 1)) * columnGap
        return horizontalInsets + presentation.artworkGutterWidth + columnWidth + gaps
    }
}
