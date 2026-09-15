# Responsive playback and track changes

## Purpose / Big Picture

The owner reports slow starting/skipping and general responsiveness. Remove audio
file opening, initial decoding, and retired decoder waits from the main actor. Keep
the queue transactional and preserve the real-time renderer's existing contract.

## Progress

- [x] 2026-09-15: Traced Play/Next and gapless preparation. File path resolution
  is asynchronous, but backend opening/priming and decoder retirement still block UI.
- [x] 2026-09-15: Recorded the controlled slow-storage baseline and added regression tests.
- [x] 2026-09-15: Added off-main preparation, stale-result rejection, and worker cleanup.
- [x] 2026-09-15: Full tests, optimized build and final audio TSan passed; installed with backup.

## Surprises & Discoveries

At baseline, `NativeAudioBackend.makeStream` opened and primed files synchronously. The same path
was used for the next-track preload. `retireStream` called `NativeDecoderSession.stop`
on the main actor; stop waited up to one second for a decoder and then closed its
handle even if a read is still in progress. The renderer itself does no file I/O.

A 250 ms injected storage delay held a main-actor heartbeat for 255.600042 ms
before the asynchronous seam; the full-suite measurement afterward was 0.113084 ms.
This measures scheduling delay, not time to audible output or live NAS performance.

An additional rapid decoder start/stop stress test exposed two TSan races after
polling NSThread completion. A DispatchGroup now explicitly joins decoder work
before handles are closed. Cancellation uses the atomic lifecycle so a newly
created worker always executes its completion signal. The final full suite, TSan,
and optimized build were rerun and passed after this correction. The first fixture seek test also attempted to
seek past its short fixture's end; its target was corrected to 0.01 seconds.

## Decision Log

- Limit this pass to playback preparation/retirement and stale-request handling.
  Keep audio formats, crossfade math, library schema, and stored media unchanged.
- Prepare a source separately from committing playback so failed/cancelled or stale
  work cannot change the queue or replace the current track.
- Keep existing synchronous backend APIs for compatibility and CD/device paths.
  User-initiated seek also uses asynchronous preparation; paused state is retained.
  The normal file-playback and next-track paths use the asynchronous preparation seam.
- Release retired streams on a cleanup worker only after the renderer returns them.
  File handles must remain valid until an in-flight read ends.

## Context and Orientation

`PlaybackEngine.playResolving` resolves a stored path before calling backend play.
`NativeAudioBackend` owns Core Audio and transfers retained streams to `RenderKernel`.
`NativeDecoderSession` owns the file handle and decoder worker. Changes must preserve
that ownership, cancellation, the last-good queue, and output sample-rate matching.

## Plan of Work

Introduce an internal prepared-source backend interface. Native preparation runs
opening/seeking/priming on a worker. PlaybackEngine validates its request generation
after preparation and then commits synchronously. Apply the same seam to preloads.
Move returned-stream cleanup off-main, keeping file handles alive during cancellation.
Test delayed reads, superseding play, stop, failure, preload, and retirement.

## Concrete Steps

Work in the publication repository. Preserve before-images/logs in
`/private/tmp/songbird-performance-2z4grgbw`. Use synthetic files and delayed fixture
sources. Run isolated focused tests, `./check.sh quick -j 4`, optimized packaging,
and `scripts/test-audio-tsan.sh` including the new concurrency cases. Refresh the
manifest, preserve the installed app, and install the checked build.

## Validation and Acceptance

A delayed source open/prime must allow a main-actor heartbeat before preparation
finishes. A stale or cancelled request must never commit playback. Failed preparation
must preserve the current queue. Retiring a blocked decoder must not stall UI or
close its handle under an active read. Existing gapless/format/queue tests must pass.
Record controlled timing separately from live rendered latency and physical hardware.

## Idempotence and Recovery

No library migration or real-media writes. Before-images and installed-app backups
permit rollback. Unsubmitted prepared sources must be reclaimed; render-owned
sources are reclaimed only after retirement events.

## Artifacts and Notes

Performance evidence must identify its fixture, build, and measurement boundary.
Do not interpret idle sampling or synthetic delay as measured real-world NAS latency.

## Interfaces and Dependencies

Add only an internal prepared-source protocol and native ownership helper. Keep the
public PlayerBackend protocol compatible. No new package or testing framework.

## Outcomes & Retrospective

Normal playback preparation, file preloading, and seeking now run off-main; stale
results cannot replace newer playback, and failed preparation preserves the current
track. Retired decoder work is explicitly joined on the cleanup worker.

Final validation on the changed tree:

- `./check.sh quick -j 4`: 310 XCTest cases (two optional-store skips), plus
  334 Swift Testing cases in 43 suites; zero failures.
- `./scripts/test-audio-tsan.sh`: 37 cases including 40 immediate worker-retirement
  iterations across WAV/FLAC; no TSan warnings. The earlier failing stress log is retained.
- `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/tests -p 'test_*.py' -v`:
  109 cases, two optional vendor rebuild skips, zero failures.
- `SONGBIRD_OFFLINE_DEPS=1 ./build.sh /private/tmp/songbird-performance-2z4grgbw/Songbird.app`:
  optimized package passed in 97.55 s; ad-hoc signatures and all 44 installed bundle
  file/link entries verified. Package.resolved bytes were restored after SwiftPM.
- Final controlled 250 ms delay: main-actor heartbeat 0.016042 ms. This is an isolated
  scheduling regression check, not a measurement of perceived responsiveness.

Installed `/Applications/Songbird.app`, preserving Last.fm application configuration,
all resources, and version 0.1.0. Backup:
`/Users/aji/project/songbird-public-verification/installed-backups/Songbird-20260915T234117Z.app`.
Source hashes, exact logs, log hashes, and installation receipt:
`/Users/aji/project/songbird-public-verification/playback-performance-20260915/`.
The running user session was not quit or relaunched. No real library/media was read
or changed. Physical CD playback/ripping/eject were previously owner-tested; this
pass does not rerun them. AirPlay, live NAS latency, audible onset, and rendered UI
responsiveness remain unmeasured. Core Audio configuration/device recovery may still
block the control actor; the completed scope is file preparation and retirement.
