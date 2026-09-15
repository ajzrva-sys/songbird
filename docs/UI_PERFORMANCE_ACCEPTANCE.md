# UI Performance Acceptance

## Automated verification

Current implementation evidence was collected on 2026-08-09 from the existing dirty working tree.
Results apply to that exact tree, not just its base commit. Before source changes,
`swift test --filter UIProjectionPerformanceTests` passed 23 cases and
`swift test --filter AlbumGridInteractionTests` passed 8. On the final implementation tree the
focused suites pass 30 projection cases, 9 album-grid cases, 15 action-handler cases, and 4
usability-fixture cases.

- [x] 10,000-track filtering, sorting, duration, index lookup, and shift-range fixture —
  `UIProjectionPerformanceTests / Ten-thousand-track projection filters, sorts, totals, and indexes without selection input`
- [x] Selection changes do not invoke the projection worker — the same 10,000-track test records
  the worker invocation count before and after selection-range work.
- [x] Sort-only changes execute through `TrackTableProjectionWorker`, retain the old immutable
  projection until the newest request completes, and preserve precomputed display values —
  `UIProjectionPerformanceTests / Sort-only projection work stays on the worker and preserves presentation values`.
- [x] Album-grid filtering, sorting, lookup, details, and context-selection order are memoized by
  revision/query/favorite/sort request, and selection-only work does not rerun the worker —
  `AlbumGridInteractionTests / Album grid projection memoizes input and resolves selected context in display order`.
- [x] Collection sources and cascading facets reuse one revision and invalidate together on the
  next revision; Recently Added retains snapshot order —
  `UIProjectionPerformanceTests / Collection and facet derivation caches reuse a revision and reset for the next`.
- [x] Track, album, playlist, persistent-model, and album-group indexes retain projection/action
  behavior, including ordered duplicate track resolution — covered by projection, stale-target,
  playlist-order, and action-handler tests.
- [x] Table cells consume immutable display values for dates, durations, sizes, rates, counts, and
  fallback labels; stable columns are iterated directly without per-row enumerated arrays —
  `UIProjectionPerformanceTests / Sort-only projection work stays on the worker and preserves presentation values`.
- [x] Bounded track, album, playlist, album-favorite, and track-favorite changes patch the snapshot
  without a full rebuild and route subsystem revisions; oversized, invalidated-all, unknown, and
  failed patches rebuild, while a failed rebuild preserves the last good snapshot — the three new
  incremental-publication tests plus the existing last-good test.
- [x] Playback clock changes do not publish through presentation or volume state —
  `UIProjectionPerformanceTests / Playback clock changes do not publish through presentation or volume surfaces`
- [x] SwiftData save routing and deleted-model resolution —
  `UIProjectionPerformanceTests / Save routing ignores unrelated entities and schedules relevant refreshes` and
  `Snapshot actor returns values and deleted models no longer resolve`
- [x] Last-good snapshot preservation after rebuild failure —
  `UIProjectionPerformanceTests / A failed rebuild preserves the last good snapshot`
- [x] Manual and smart playlist projection parity —
  `UIProjectionPerformanceTests / Manual playlist order and snapshot smart rules are preserved`
- [x] Multi-disc album grouping and artwork retention —
  `UIProjectionPerformanceTests / Album projection groups multi-disc values and retains available artwork`
- [x] Thumbnail downsampling, in-flight deduplication, cache limits, remote CD artwork, and targeted invalidation —
  `ArtworkThumbnailServiceTests / Thumbnails downsample, deduplicate in flight, obey limits, and invalidate by album`
- [x] Import progress burst suppression and forced final publication —
  `ImportMaintenancePerformanceTests / Import progress suppresses bursts and force always publishes final state`
- [x] Maintenance cancellation —
  `ImportMaintenancePerformanceTests / Maintenance worker honors cancellation`
- [x] Full Swift test suite — `./check.sh quick` passed on the 2026-08-09 implementation tree:
  170 XCTest cases with 2 expected skips and 201 Swift Testing cases in 28 suites, with 0 failures.
- [x] Optimized release build — `swift build -c release` passed.
- [ ] **Needs verification on the current tree:** direct and sandbox package signing. Packaging was
  not authorized for this evidence pass. Historical 2026-08-02 evidence in `TESTING.md` covers
  disposable direct/usability package signing and parity, but no recorded sandbox-package signing
  run supports the original combined checkbox.

These automated checks prove deterministic projection, invalidation, fallback, cadence,
cancellation, and build behavior.
They do not prove rendered latency, main-thread responsiveness, accessibility, signing policy,
hardware behavior, or release readiness; those remain in the hands-on matrix below.

## Retained performance signposts

- `LibrarySnapshot / Snapshot rebuild`
- `TrackTableProjection / Table projection`
- `AlbumProjection / Album grouping`
- `ArtworkThumbnail / Thumbnail decode`
- `LibraryMaintenance` operation intervals

The audio render callback is intentionally not instrumented.

## Disposable rendered evidence

Run `20260809T172639Z-48685` used a package-parity-checked release app with an isolated profile
containing exactly 10,000 tracks, 1,000 albums, and 4 playlists. Time Profiler captured two table
sorts and track/album/Recently Added navigation. Its samples place
`TrackTableProjectionWorker.sort` on worker thread `0x4685b0`, distinct from main thread
`0x46853f`; album-grid projection also appears on a worker thread. The trace is retained at
`.build/usability/runs/20260809T172639Z-48685/artifacts/time-profiler.trace`.

This does not close the rendered gate. The AX-driven trace reported 497.61 ms and 420.65 ms
microhangs plus one 836.60 ms main-thread hang while semantic selectors traversed/replaced the
10,000-row table. That input path exposes the full accessibility tree and is not a clean native
pointer baseline, so the samples are neither dismissed nor attributed to ordinary interaction.
The SwiftUI template completed with `Trace file had no SwiftUI data`. Screen Recording permission
was unavailable, so there is no screenshot/frame evidence. The disposable app and broker were
stopped; the normal Songbird app and library were never opened or changed.

## Hands-on acceptance matrix

These checks require the running release app and cannot be established by unit tests alone.

- [ ] SwiftUI Instruments and Time Profiler: repeat with native pointer/keyboard input and usable
  SwiftUI frame data; Time Profiler's off-main sort evidence alone is complete
- [ ] Resize the cascade divider and track columns continuously for five seconds
- [ ] Scroll, search, select, and navigate the album grid with screenshot/frame evidence; the
  current run has window-only AX action traces but no visual evidence
- [ ] Run main and mini playback with Settings open; confirm only timeline leaves update at 10 Hz
- [ ] Import 1,000 files and run every hygiene operation; confirm no filesystem traversal on the main thread
- [ ] Smoke-test CD playback, artwork, selection, ripping, and eject
- [ ] Accessibility Inspector: track table, divider, player bars, album grid, sidebar, and Settings
- [ ] Keyboard: Tab, arrows, Return/Space, Escape, and adjustable divider actions
- [ ] VoiceOver: row summaries, artwork labels, favorite state, player controls, and resize feedback
- [ ] Reduce Motion: layout editor transitions do not animate

Use the direct release build for the first pass. The sandbox CD row remains gated by the signed hardware matrix in `CD_HARDWARE_MATRIX.md`.
