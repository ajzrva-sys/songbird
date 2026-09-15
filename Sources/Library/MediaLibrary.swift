import SwiftData
import Foundation

@MainActor
public final class MediaLibrary {
    public static let shared = MediaLibrary()

    public let container: ModelContainer
    public let startupError: String?

    private init() {
        MediaLibraryStore.migrateLegacyStoreIfNeeded()
        let schema = Schema(versionedSchema: SongbirdSchemaV4.self)
        let config = ModelConfiguration(
            schema: schema,
            url: MediaLibraryStore.libraryStoreURL,
            cloudKitDatabase: .none
        )
        let opened = Self.openContainer(schema: schema, configuration: config)
        container = opened.container
        startupError = opened.error
    }

    public var context: ModelContext {
        container.mainContext
    }

    static func openContainer(
        schema: Schema,
        configuration: ModelConfiguration
    ) -> (container: ModelContainer, error: String?) {
        do {
            return (
                try ModelContainer(
                    for: schema,
                    migrationPlan: SongbirdMigrationPlan.self,
                    configurations: configuration
                ),
                nil
            )
        } catch let migrationError {
            // Older development builds wrote stores whose model hash is no
            // longer present in the staged plan, even though their schema is
            // compatible with the current model. Let Core Data perform its
            // normal inferred/lightweight compatibility check before treating
            // the library as unusable. A genuinely incompatible or damaged
            // store still falls through to the preserved-backup path below.
            do {
                let compatibleContainer = try ModelContainer(
                    for: schema,
                    configurations: configuration
                )
                NSLog(
                    "Songbird: Opened library with lightweight compatibility fallback after staged migration failed: %@",
                    "\(migrationError)"
                )
                return (compatibleContainer, nil)
            } catch let compatibilityError {
                NSLog(
                    "Songbird: Lightweight compatibility fallback failed: %@",
                    "\(compatibilityError)"
                )
            }

            let storeURL = configuration.url
            let backupURL = try? MediaLibraryStore.backupStore(at: storeURL)
            let location = backupURL?.path ?? storeURL.path
            let message = "Songbird could not migrate the library. "
                + "The original database was preserved; a backup is at \(location). "
                + "Quit Songbird and restore or inspect the database before importing."
            NSLog("Songbird: %@ Migration error: %@", message, "\(migrationError)")
            do {
                let recovery = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: true,
                    cloudKitDatabase: .none
                )
                return (
                    try ModelContainer(
                        for: schema,
                        migrationPlan: SongbirdMigrationPlan.self,
                        configurations: recovery
                    ),
                    message
                )
            } catch {
                fatalError("Failed to create recovery ModelContainer: \(error)")
            }
        }
    }
}
