# Golden Principles

These are repository-derived rules, not generic style advice. Apply them unless a task presents newer primary-repo evidence.

## 1. Keep real-time audio work bounded and ownership-explicit

- Principle: Render/decode callbacks do no allocation, blocking, logging, file access, collection mutation, UI/user callbacks, or Swift object destruction.
- Evidence: `AUDIO_ENGINE.md`, `RenderKernel.swift`, atomic/ring-buffer targets and tests.
- Why: Unbounded work or unclear ownership can cause audible glitches, races, and use-after-free failures.
- Apply: Transfer immutable snapshots/events through fixed-capacity queues; reclaim objects on the control side.
- Mechanical enforcement: TSan subset, focused render tests, and a future callback-forbidden-API scan.
- Exceptions/unknowns: None documented; any exception requires an audio ExecPlan and measured proof.

## 2. Validate playback before committing queue state

- Principle: A failed file/backend start must not destroy or rewrite the user's current queue.
- Evidence: `PlaybackSession.startReplacement`, `playOccurrence`, `PlaybackEngine.play`, and playback tests; the dated audit documents the earlier failure mode.
- Why: Queue state is user intent and must remain trustworthy after media failure.
- Apply: Prepare the source first; commit replacement/promotion only through the success closure.
- Mechanical enforcement: Tests for missing/corrupt files with prior queue/history assertions.
- Exceptions/unknowns: Explicit Stop/Clear commands may mutate queue by user request.

## 3. Separate domain identity from UI occurrence identity

- Principle: Repeated occurrences of one track need unique queue-entry IDs; `Track.id` remains the library identity.
- Evidence: `PlaybackQueueEntry`, `PlaybackQueue`, `PlaybackSession`, and shuffle/queue tests.
- Why: SwiftUI diffing, focus, move, removal, and history must target one occurrence deterministically.
- Apply: Pass occurrence IDs for row-specific queue actions and track IDs for library mutations.
- Mechanical enforcement: Duplicate-entry reorder/remove/focus tests.
- Exceptions/unknowns: Deduplicated library collections should continue to use model identity.

## 4. Present immutable snapshots; resolve models at mutation boundaries

- Principle: Large library views consume `LibrarySnapshot` and projection values rather than repeatedly fetching/traversing SwiftData models in view bodies.
- Evidence: `LibrarySnapshotStore`, `TrackTableProjectionWorker`, `LibraryAlbumProjectionStore`, app environment injection, and performance acceptance tests.
- Why: It keeps persistence work off hot UI paths and stabilizes view identity/state.
- Apply: Extend snapshot/projection inputs for new read data; use `LibraryItemActionHandler` to resolve models for writes.
- Mechanical enforcement: Projection tests and performance signposts; future structural checks for direct view fetches require careful exceptions.
- Exceptions/unknowns: Small editor/detail mutations may require live models through the injected container.

## 5. Preserve user data before recovery

- Principle: Migration/open failure preserves the original library, reports a recoverable path, and uses in-memory fallback rather than silently replacing data.
- Evidence: `MediaLibrary.openContainer`, `MediaLibraryStore.backupStore`, migration/recovery tests.
- Why: A music library is durable user data; startup success is not worth destructive recovery.
- Apply: Version schemas explicitly, test prior-store fixtures, and make retry/backup behavior part of acceptance.
- Mechanical enforcement: Migration tests for compatible, duplicate-path, corrupt, and optional real legacy stores.
- Exceptions/unknowns: Development-only fixture reset is allowed only inside a disposable test root.

## 6. Test UI against a disposable profile and fail closed

- Principle: Automated UI work must never fall back to the user's normal Songbird store or expose real file/history data.
- Evidence: `MediaLibraryStore.resolvedApplicationSupportDirectory`, `scripts/ai-usability`, `scripts/usability/ui`, `Usability/AI_TESTER.md`.
- Why: Black-box automation opens windows, imports fixture state, and captures evidence; unsafe fallback could corrupt or reveal personal data.
- Apply: Require `SONGBIRD_UI_TEST_ROOT`, alternate bundle IDs, window-only snapshots, and blocked filesystem/external-service actions.
- Mechanical enforcement: Store-root safety tests, wrapper exit codes, and fixture tests.
- Exceptions/unknowns: Human manual testing of the normal app is outside automation and requires explicit intent.

## 7. Prefer native outcome parity over legacy implementation parity

- Principle: References inform behavior and vocabulary; current macOS requirements, source, and tests decide implementation.
- Evidence: `PARITY.md`, `Usability/PRODUCT_REQUIREMENTS.md`, historical revival/classic UI plans.
- Why: Nightingale, Museeks, and Cog use different platforms, frameworks, licenses, and constraints.
- Apply: Name the exact reference behavior, verify it, implement it natively, and test the observable result without copying source.
- Mechanical enforcement: ExecPlan parity sections and review checklist.
- Exceptions/unknowns: Asset reuse requires explicit provenance/license evidence.

## 8. Respect SwiftPM target and resource boundaries

- Principle: Shared declarations crossing from `SongbirdLib` to `Songbird` are public; package resources use `Bundle.module`.
- Evidence: `Package.swift`, current `SongbirdApp` imports, and July 2026 commits fixing resource/public-boundary issues.
- Why: Debugging access-control or bundle-path failures wastes time and can pass in one packaging context but fail in another.
- Apply: Put reusable code in shared source areas, expose only required APIs, and resolve packaged resources through SwiftPM.
- Mechanical enforcement: Full package build/tests and targeted resource-loading tests.
- Exceptions/unknowns: App-only types under `Sources/App/` need not be public.

## 9. Treat native interaction and accessibility as correctness

- Principle: Standard macOS pointer/keyboard semantics, labels, focus, resizing, and recovery are functional requirements, not polish.
- Evidence: `Usability/PRODUCT_REQUIREMENTS.md`, `AI_TESTER.md`, interaction/usability tests, and `CODE_AUDIT.md` findings.
- Why: Custom controls that look correct can still break Space/Return, selection, VoiceOver, or window use.
- Apply: Prefer native controls/commands, test focused-control behavior, and verify observable UI through the isolated harness.
- Mechanical enforcement: Coordinator/value tests, AX validation, black-box action traces, and manual accessibility matrix.
- Exceptions/unknowns: Custom controls require explicit semantic and keyboard behavior tests.

## 10. Do not convert manual gates into inferred passes

- Principle: Hardware, signing, audio continuity, Instruments, and accessibility rows pass only with current recorded evidence.
- Evidence: both hardware matrices and `docs/UI_PERFORMANCE_ACCEPTANCE.md`.
- Why: Unit tests cannot emulate every device, entitlement, timing, or assistive-technology behavior.
- Apply: Record exact environment/device/build/result and leave unavailable rows pending.
- Mechanical enforcement: Review checklist and dated evidence sections.
- Exceptions/unknowns: None; simulation can supplement but not replace a named manual gate.
