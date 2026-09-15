import Foundation
import SwiftData

public enum AlbumRelationshipMaintenance {
    private static let completionKey = "songbird.albumRelationships.physicalIdentity.v2"
    @MainActor private static var task: Task<Bool, Never>?

    @MainActor
    public static func runIfNeeded(in container: ModelContainer) async -> Bool {
        if UserDefaults.standard.bool(forKey: completionKey) { return true }
        if let task { return await task.value }

        let repairTask = Task {
            do {
                _ = try await AlbumRelationshipReconciler.reconcile(in: container)
                UserDefaults.standard.set(true, forKey: completionKey)
                return true
            } catch {
                LibraryStatus.shared.showNotice(
                    "Album organization could not be repaired: \(error.localizedDescription)",
                    severity: .warning
                )
                return false
            }
        }
        task = repairTask
        let completed = await repairTask.value
        task = nil
        return completed
    }

    @MainActor
    public static func startIfNeeded(in container: ModelContainer) {
        Task { _ = await runIfNeeded(in: container) }
    }

    static func repairLibrary(in container: ModelContainer) async -> Bool {
        do {
            _ = try await AlbumRelationshipReconciler.reconcile(in: container)
            return true
        } catch {
            return false
        }
    }
}
