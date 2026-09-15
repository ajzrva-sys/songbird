# Architecture Map

## Purpose and Runtime Shape

Songbird is a macOS 14+ SwiftUI application for importing, organizing, and playing a local music library and audio CDs. `Package.swift` defines a shared `SongbirdLib` library, the `Songbird` executable, C bridge targets, diagnostic/helper executables, and one test target. SwiftData owns the library store; the playback path uses AVFoundation/AudioToolbox plus a standalone libFLAC bridge.

This map describes the 2026-08-02 working tree, including uncommitted files. Historical plans and commit history describe older states and must not override current source.

## Package and Directory Ownership

| Area | Responsibility | Primary entry points |
|---|---|---|
| `Sources/App/` | App lifecycle, scenes, commands, dependency composition, AppKit bridges. | `SongbirdApp.swift`, `AppDelegate.swift` |
| `Sources/Views/` | Main/mini windows, navigation destinations, library surfaces, editors, settings, queue, now playing. | `MainView.swift`, `LibraryContentView.swift`, `TrackTableProjectionView.swift`, `NowPlayingBar.swift` |
| `Sources/ServicePane/` | Sidebar destinations, rows, playlist section, artwork well. | `ServicePaneView.swift`, `ServicePaneItem.swift` |
| `Sources/Library/` | SwiftData models/schema, migrations, import, snapshots, projections, artwork, maintenance, playlists. | `MediaLibrary.swift`, `SongbirdSchema.swift`, `LibraryImportPipeline.swift`, `LibrarySnapshotStore.swift` |
| `Sources/Playback/` | Queue identity/order, transactional playback start, transport coordination, MediaPlayer commands. | `PlaybackSession.swift`, `PlaybackEngine.swift`, `PlaybackQueue.swift` |
| `Sources/Backend/` | Playback abstraction, file decoding, real-time renderer, device recovery, diagnostics. | `PlayerBackend.swift`, `NativeAudioBackend.swift`, `NativeDecoderSession.swift`, `RenderKernel.swift` |
| `Sources/AudioAtomics/` | C11 atomic queues/counters used across real-time boundaries. | `SBAudioAtomics.c`, public header |
| `Sources/FLACBridge/` | C bridge to the vendored libFLAC decoder. | `SBFLACDecoder.c`, public headers |
| `Sources/OpticalDisc/` | Disc discovery, TOC/sector reading, metadata lookup/cache, playback source, ALAC ripping. | `OpticalDiscService.swift`, `AudioCDReader.swift`, `AudioCDRipper.swift` |
| `Sources/OpticalDiscBridge/` | IOKit bridge for optical-disc access. | `SBOpticalDiscBridge.c`, public header |
| `Sources/Discogs/` | Token storage, Discogs requests/cache, single and bulk artwork UI. | `DiscogsClient.swift`, `DiscogsKeychain.swift` |
| `Sources/Integrations/` | Last.fm client and shared credential migration/storage. | `LastFMClient.swift`, `SongbirdCredentialStore.swift` |
| `Sources/Utils/` | Theme, player layout, preferences, dock icon, notifications, pasteboard. | `Theme.swift`, `PlaybackSettings.swift` |
| `Sources/DockIconSupport/` | Small AppKit-only renderer and shared preference/notification identifiers for themed Dock artwork. | `SongbirdDockIconArtwork.swift` |
| `Sources/DockTilePlugin/` | Retained-Dock rendering while the main app is not running. | `SongbirdDockTilePlugin.swift` |
| `Tools/` | Disposable usability fixture builder and accessibility/UI probe. | `SongbirdUsabilityFixture/`, `SongbirdUIProbe/` |
| `Tests/SongbirdTests/` | XCTest and Swift Testing coverage for library, playback, audio, UI coordinators, preferences, and usability seams. | Test filenames mirror production concern. |
| `config/` | Direct, sandbox, and CD probe entitlements. | `Songbird.*.entitlements`, `CDSandboxProbe.entitlements` |
| `scripts/` | Packaging, audio fixtures/TSan, and isolated usability automation. | See `TOOLS.md`. |

`Package.swift` also links GRDB 6.29.3 into `SongbirdLib`; no direct `import GRDB` was found in the surveyed Swift sources. Needs verification before removing or relying on that dependency.

## App Composition and Control Flow

`SongbirdApp.init()` creates one `PlaybackSession`, `LibrarySnapshotStore`, `LibraryAlbumProjectionStore`, navigation coordinator, search coordinator, and library action handler. The main scene injects those objects and `MediaLibrary.shared.container` into `MainView` and its descendants. `AppDelegate` receives the playback session for application-level actions.

`MainView` owns the sidebar/content/player-bar layout. A `NavigationStack` routes root sidebar destinations and album/artist/genre detail routes. `LibraryItemActionHandler` is the shared mutation/action boundary for views; future UI work should extend that boundary rather than give individual views unrelated persistence flows.

## Library Data Flow

```text
files/folders -> LibraryScanner -> LibraryImportPipeline -> SwiftData ModelContainer
                                                        -> save notifications
save notifications -> LibrarySnapshotStore worker -> immutable LibrarySnapshot
LibrarySnapshot -> table/album projection workers -> SwiftUI views
UI action -> LibraryItemActionHandler -> main ModelContext -> save -> snapshot refresh
```

- `MediaLibrary` opens schema V3 with `SongbirdMigrationPlan` and a fixed Application Support store path.
- On staged migration failure it tries a lightweight compatibility open; on genuine failure it preserves/backs up the store and falls back to an in-memory container with a visible error.
- Background model actors/workers build immutable, sendable snapshots and projections. Views resolve persistent models only when a mutation requires them.
- Bulk imports bracket snapshot publication through `LibrarySnapshotStore.beginBulkUpdates()` / `endBulkUpdates()`.
- `SONGBIRD_UI_TEST_ROOT` redirects only the disposable usability/test store. `MediaLibraryStore` rejects empty, relative, or unsafe overrides rather than falling back to the real library.

## Playback Data Flow

```text
view action -> PlaybackSession -> validate/prepare PlaybackEngine request
            -> commit PlaybackQueue mutation only after backend accepts source
PlaybackEngine -> PlayerBackend -> NativeAudioBackend
file source -> NativeDecoderSession -> SPSC RingBuffer -> RenderKernel -> AVAudioSourceNode
CD source   -> AudioCDReader      -> SPSC RingBuffer -> RenderKernel -> AVAudioSourceNode
render events -> backend control thread -> PlaybackEngine -> observable presentation state
```

- Queue entries have occurrence IDs distinct from `Track.id`, permitting repeated tracks.
- `PlaybackSession` is the transaction boundary for queue replacement/promotion and playback start.
- The backend, not UI timers, owns gapless and equal-power crossfade frame timing.
- The renderer consumes immutable snapshots through fixed-capacity atomic queues; object release and callbacks happen on the control side.
- Output-device and sleep/wake recovery rebuild the engine and resume the same source near its confirmed position.
- See `AUDIO_ENGINE.md` for detailed invariants and diagnostics.

## Optical Disc Flow

`OpticalDiscService` discovers/ejects drives through DiskArbitration and an IOKit bridge. TOC parsing produces `AudioDisc`/`AudioCDSource` values. `AudioCDReader` implements the same buffered PCM-source contract as file decoding. Metadata can come from CD-Text, MusicBrainz, or a Discogs fallback; ripping writes ALAC through `AudioCDRipper` and imports the result through library code.

Hardware and sandbox behavior are not proven by unit tests. `docs/CD_HARDWARE_MATRIX.md` is the release gate.

## Boundaries and Invariants

- `Sources/App/` imports `SongbirdLib`; any shared declaration crossing that target boundary must be `public`.
- The Dock tile plug-in must stay independent of `SongbirdLib`; it links only the small AppKit icon-support target so the system Dock process never loads library, playback, database, or integration code.
- SwiftPM resources under `Sources/Resources/` are accessed through `Bundle.module`.
- UI code may observe playback state but must not schedule audio transitions.
- Render/decode callbacks must not allocate, block, log, access files, call UI/user code, mutate collections, or destroy Swift objects.
- SwiftData migration and maintenance code must preserve recoverability and must never run against a user's store during test automation.
- Credentials belong in Keychain-backed stores; `UserDefaults` holds non-secret preferences and migration markers.
- Reference trees are behavioral/design evidence only. Native Swift architecture and current product requirements take precedence.

## External Dependencies and Platform Services

- Swift package: GRDB.swift 6.29.3, pinned in `Package.resolved`.
- Vendored runtime: `Vendor/FLAC/libFLAC.14.dylib` and `libogg.0.dylib` plus notice.
- Apple frameworks: SwiftUI, SwiftData, AppKit, AVFoundation, AudioToolbox, MediaPlayer, DiskArbitration, IOKit, Security, OSLog.
- Optional network features: Discogs, MusicBrainz, and Last.fm. Do not use real credentials or network calls in deterministic tests.
- Hardware/permissions: audio output devices, optical drives, Accessibility, Screen Recording, and signing entitlements for specialized validation.

## Test Routing

| Changed area | Start with | Additional gate |
|---|---|---|
| Library/schema/import | Matching `Tests/SongbirdTests/*Migration*`, `Library*`, or `TrackImporter*` tests | Full `./check.sh quick`; use disposable stores only. |
| Queue/playback coordination | `PlaybackEngineTests`, `PlaybackQueueShuffleTests` | Full quick suite. |
| Backend/render/atomics | `AudioAtomicTests`, `NativeAudioBackendTests`, `AudioDiagnosticsPollerTests` | TSan script and manual audio matrix before release. |
| Optical disc | `AudioCDFeatureTests`, `AudioCDRipperTests`, `AudioCDTOCParserTests` | CD hardware matrix before release. |
| UI coordinators/preferences | Matching interaction, navigation, theme, column, or usability tests | Isolated black-box usability run for user-facing claims. |
| Packaging/entitlements | Build/package/codesign commands in `TESTING.md` | Direct and sandbox checks; hardware where applicable. |

## Edit Routing and Fragile Files

- App dependency/lifecycle change: begin at `Sources/App/SongbirdApp.swift`; preserve disposable-test switches and model-container injection.
- Library mutation: use `LibraryItemActionHandler` and `MediaLibrary`/model actors; do not let views silently save independent contexts.
- Read performance: extend snapshot/projection types rather than adding repeated SwiftData fetches to view bodies.
- Playback behavior: begin at `PlaybackSession`/`PlaybackEngine`; change the backend only for audio mechanics.
- Renderer/decoder changes: inspect `AUDIO_ENGINE.md`, atomic/ring-buffer tests, and TSan gate first. These files are high risk.
- Schema changes: require an ExecPlan, versioned schema stage, migration fixture strategy, and recovery validation.
- Packaging changes: inspect both entitlements and `scripts/package-songbird.sh`; it deletes/rebuilds its target app bundle.
- Avoid `Vendor/FLAC/`, reference trees, generated `.build/`, and `Songbird.app/` unless explicitly tasked.

## Known Architectural Gaps

- `CODE_AUDIT.md` records high-severity UI/concurrency findings from 2026-08-01, but the working tree changed afterward; each finding needs revalidation before implementation.
- No repository CI, formatter, linter, or docs-structure check was found.
- Several large SwiftUI files remain identified by the dated audit; size alone is not authorization to refactor them.
- Direct-versus-sandbox audio-CD support is unresolved pending signed hardware checks.
- The intended long-term role and retention policy of all reference trees needs human confirmation; see `PARITY.md`.

## Needs Verification

- Whether GRDB remains intentionally linked despite no surveyed direct imports.
- Which historical `.hermes/plans/` work is complete, superseded, or still desired.
- Whether all checked claims in `docs/UI_PERFORMANCE_ACCEPTANCE.md` correspond to the current uncommitted tree.
