import Foundation
import AppKit
import UniformTypeIdentifiers
import CoreTransferable

/// Drag payload for moving track IDs onto playlists.
public struct TrackIDPasteboard: Codable, Transferable, Equatable {
    public var ids: [UUID]

    public init(ids: [UUID]) {
        self.ids = ids
    }

    /// Creates the provider only when a drag actually begins, avoiding eager
    /// selection ordering and payload encoding for every visible table row.
    public func itemProvider() -> NSItemProvider {
        guard let data = try? JSONEncoder().encode(self) else { return NSItemProvider() }
        return NSItemProvider(
            item: data as NSData,
            typeIdentifier: UTType.songbirdTrackIDs.identifier
        )
    }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .songbirdTrackIDs)
        ProxyRepresentation { (payload: TrackIDPasteboard) in
            payload.ids.map(\.uuidString).joined(separator: ",")
        }
    }
}

public extension UTType {
    static let songbirdTrackIDs = UTType(
        exportedAs: "com.songbird.track-ids",
        conformingTo: .data
    )
}

@MainActor
enum TrackIDDropDecoder {
    static func decode(
        providers: [NSItemProvider],
        completion: @escaping @MainActor ([UUID]) -> Void
    ) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.songbirdTrackIDs.identifier) {
                _ = provider.loadTransferable(type: TrackIDPasteboard.self) { result in
                    Task { @MainActor in
                        guard case .success(let payload) = result else { return }
                        completion(payload.ids)
                    }
                }
                return true
            }
            if provider.canLoadObject(ofClass: NSString.self) {
                _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                    guard let string = object as? String else { return }
                    let ids = string.split(separator: ",").compactMap {
                        UUID(uuidString: String($0))
                    }
                    Task { @MainActor in completion(ids) }
                }
                return true
            }
        }
        return false
    }
}
