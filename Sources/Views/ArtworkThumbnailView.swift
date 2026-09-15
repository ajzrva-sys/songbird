import AppKit
import SwiftUI

public struct ArtworkThumbnailView: View {
    public let reference: ArtworkReference?
    public let pointSize: CGSize
    public let accessibilityLabel: String
    public var cornerRadius: CGFloat
    public var contentMode: ContentMode
    public var placeholderSymbol: String
    public var placeholderColor: Color
    public var tintColor: Color

    @Environment(\.displayScale) private var displayScale
    @ObservedObject private var discogsClock = DiscogsPresentationClock.shared
    @State private var loadState = ArtworkThumbnailLoadState()

    public init(
        reference: ArtworkReference?,
        pointSize: CGSize,
        accessibilityLabel: String,
        cornerRadius: CGFloat = 3,
        contentMode: ContentMode = .fill,
        placeholderSymbol: String = "music.note",
        placeholderColor: Color = .secondary.opacity(0.12),
        tintColor: Color = Color.black.opacity(0.88)
    ) {
        self.reference = reference
        self.pointSize = pointSize
        self.accessibilityLabel = accessibilityLabel
        self.cornerRadius = cornerRadius
        self.contentMode = contentMode
        self.placeholderSymbol = placeholderSymbol
        self.placeholderColor = placeholderColor
        self.tintColor = tintColor
    }

    public var body: some View {
        VStack(spacing: 2) {
            thumbnail
            if let evidence = reference?.discogsEvidence, evidence.isFresh(at: discogsClock.now), let page = evidence.sourcePageURL {
                DiscogsAttributionView(sourcePageURL: page)
            }
        }
    }

    private var available: Bool { reference?.isAvailable(at: discogsClock.now) ?? true }

    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(placeholderColor)
                .overlay {
                    if ArtworkThumbnailPlaceholderPolicy.showsSymbol(
                        hasLoadedImage: available && loadState.image != nil
                    ) {
                        Image(systemName: placeholderSymbol)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                }
            if available, let image = loadState.image {
                Image(nsImage: NSImage(
                    cgImage: image,
                    size: CGSize(width: CGFloat(image.width), height: CGFloat(image.height))
                ))
                    .renderingMode(reference == .songbirdLogo ? .template : .original)
                    .resizable()
                    .aspectRatio(
                        CGFloat(image.width) / CGFloat(max(image.height, 1)),
                        contentMode: contentMode
                    )
                    .foregroundStyle(tintColor)
            }
        }
        .frame(width: pointSize.width, height: pointSize.height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIgnoresInvertColors()
        .onReceive(discogsClock.$now) { now in
            loadState.expire(reference: reference, at: now)
        }
        .onReceive(NotificationCenter.default.publisher(for: ArtworkInvalidation.notificationName)) { notification in
            guard let event = ArtworkInvalidation(notification: notification),
                  event.affects(reference) else { return }
            loadState.invalidate(event, reference: reference)
        }
        .task(id: TaskKey(
            reference: available ? reference : nil, pointSize: pointSize, scale: displayScale,
            generation: loadState.generation
        )) {
            let generation = loadState.generation
            loadState.publish(nil, generation: generation)
            guard available else { return }
            let reference = reference ?? .missingAlbumArtwork
            let image = await ArtworkThumbnailService.shared.image(
                for: reference,
                pointSize: pointSize,
                scale: displayScale
            )
            guard Task.isCancelled == false, reference.isAvailable(at: DiscogsClock.sample()) else { return }
            loadState.publish(image, generation: generation)
        }
    }

    private struct TaskKey: Hashable {
        let reference: ArtworkReference?
        let width: Int
        let height: Int
        let scale: Int
        let generation: UInt64

        init(reference: ArtworkReference?, pointSize: CGSize, scale: CGFloat, generation: UInt64) {
            self.reference = reference
            self.generation = generation
            width = Int(pointSize.width.rounded())
            height = Int(pointSize.height.rounded())
            self.scale = Int((scale * 100).rounded())
        }
    }
}

enum ArtworkThumbnailPlaceholderPolicy {
    static func showsSymbol(hasLoadedImage: Bool) -> Bool {
        hasLoadedImage == false
    }
}
