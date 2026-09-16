# Immediate pause and reused album covers

## Purpose / Big Picture

The owner reports multi-second Pause, Go to Album, and album-cover display delays.
Make Pause act synchronously, keep database work off the UI actor, and reuse already
loaded covers across thumbnail sizes. Preserve saved images, transient expiry,
queue behavior, and the normal library.

## Progress

- [x] 2026-09-15: Traced transport, navigation, snapshot and thumbnail paths.
- [x] Add cross-size reuse, background worker creation, and immediate pause.
- [x] 2026-09-15: Isolate focused menu observation; replay the loop fix in two fresh final-build profiles.
- [x] 2026-09-15: Focused/full tests, audio TSan, optimized build and bounded disposable UI checks.
- [x] 2026-09-15: Install with backup and prepare evidence/manifest for the source handoff.

## Surprises & Discoveries

Pause uses a 22-step main-actor fade; queued UI work can extend its nominal 220 ms.
Artwork caches/joins only exact pixel sizes, so a larger detail re-fetches album bytes.
The default SwiftData model actors are constructed from UI-owned initializers;
constructing them in detached tasks avoids binding their contexts to the main queue.
ArtworkReference.resolved also touches full image bytes on the main actor even when
the library snapshot already knows which artwork reference to use.
Album routing and its immediate track projection already use cached snapshots.
The disposable UI tests exposed a separate navigation/layout stall. Native table
appearance/discovery and header-geometry experiments did not resolve it and were
reverted. Menu lookup in the probe can itself take seven seconds before input;
right-click plus keyboard menu activation avoided that overhead and still reproduced
a real multi-second detail transition stall. Disabling stack animation also failed and was reverted. Temporary SwiftUI change
logging exposed a feedback loop: focused command closures changed, the App observed
them and rebuilt its window, and the rebuilt view published new closures. Moving
those observations into a separate Commands type stopped the sustained loop in the
first live replay. All diagnostic logging was removed; two final-source replays
confirmed stable album headers/covers at 799.87 and 780.99 ms. This remains above
the 250 ms product target and is retained as PERF-ALBUM-250, not claimed as passed.


## Decision Log

- Pause cancels the fade and pauses the engine immediately; resume/Stop fades stay.
- Retain exact-size output quality while sharing bounded source bytes across sizes.
  Show any already-decoded cover while the detail-size image is prepared.
- Use existing snapshot/thumbnail actors and invalidation generations. No migration,
  dependency, hardware policy, or media changes. Transient Discogs expiry stays intact.
- Do not claim measured user-library latency. No running Songbird process was found
  by exact process-name lookup; controlled tests and disposable UI are the evidence.

## Context and Orientation

NativeAudioBackend owns pause; PlaybackEngine commits UI playback state.
ArtworkThumbnailService owns image cache/loads, ArtworkThumbnailView publishes images.
LibrarySnapshotStore constructs the default SwiftData reader; LibrarySnapshot contains
stable artwork references used by player/album views. The prior preparation fix at
19510c6 remains intact.

## Plan of Work

Create SwiftData workers off-main, share local album bytes across sizes and preserve
invalidation, expose cached preview lookup, and remove the deferred Pause fade.
Test reuse, replacement/expiry, cancellation, worker construction and transport.

## Concrete Steps

Work only in /Users/aji/project/songbird-public. Preserve before-images/logs under
/private/tmp/songbird-pause-artwork-qmioe4hu. Run isolated ./check.sh quick -j 4,
scripts/test-audio-tsan.sh, Python checks and ./build.sh to an external app path.
Use the repository's disposable UI wrapper for a bounded Pause/album check, then
install with a backup and verify signatures/resources/source correspondence.

## Validation and Acceptance

Repeated size requests fetch album bytes once; a cached smaller image is available
before a delayed larger decode completes. Invalidation prevents stale publication
and refreshes all affected sizes. Default worker construction occurs off-main.
Pause has no scheduled delay before engine.pause. Existing tests/TSan must pass.
Report actual rendered UI evidence separately from deterministic tests.

## Idempotence and Recovery

Keep original checkout/media untouched. Retain old installed app and source hashes.
Caches remain bounded, and late work cannot reinsert invalidated data.

## Artifacts and Notes

No user-library or real-service access. Physical CD was previously owner-tested;
AirPlay and audio-output latency are not inferred from tests.

## Interfaces and Dependencies

No public backend protocol change. Extend the thumbnail service with cached-preview
lookup and keep source caching internal. Model actor wrappers forward existing APIs.

## Outcomes & Retrospective

Immediate Pause, off-main database readers, cross-size artwork reuse and isolated
focused menu observation are implemented and installed. Final quick checks passed
310 XCTest (two skips) plus 339 Swift Testing tests; TSan passed 37 + 27 tests.
Python passed 109 checks (two skips). Optimized compilation, packaging and all 44
installed bundle entries/signatures/resources were verified; Last.fm is preserved.
The two final UI runs are 20260916T003516Z-7963 and 20260916T003700Z-8691.
Their screenshots show the correct album/cover, and the latter also verifies Select
All and Find. The first verifies Play/Pause state with silent fixture audio. Reports
are partial overall: broad UI, audible latency and hardware were not tested.

Final evidence and install receipt:
/Users/aji/project/songbird-public-verification/pause-album-artwork-20260915/.
Prior installed app: installed-backups/Songbird-20260916T003847Z.app in that parent.
Original checkout, normal library and media were preserved. The focused repair can
be archived; PERF-ALBUM-250 tracks further navigation timing work.
