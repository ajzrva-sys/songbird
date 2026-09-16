# Faster initial library display

## Purpose / Big Picture

Reduce the reported launch-to-library delay and stop showing No Results before
the first catalog read finishes. Preserve the Back fix, audio behavior, normal
library and original checkout. No schema change or new dependency.

## Progress

- [x] 2026-09-15: reproduce the false empty state in two fresh 10,000-track profiles.
- [x] 2026-09-15: measure reads/projection; reduce hidden-column work and unblock folder checking.
- [x] 2026-09-15: gate catalog-dependent views on initial read success/failure.
- [x] 2026-09-15: focused/full tests, optimized build and two isolated UI replays.
- [x] 2026-09-15: install with backup and retain evidence for source handoff.

## Surprises & Discoveries

The table projects revision zero, the placeholder empty snapshot, and marks it
loaded before the real database read finishes. Baseline initial screenshots show
No Results and zero tracks; later snapshots show all 10,000 fixture tracks.
Baseline runs: 20260916T010917Z-17703 and 20260916T010957Z-18123.

An external debug benchmark reading the same disposable 10,000-track store measured
0.614 s for its cold snapshot and 0.411 s for the default table projection. Visible
column formatting reduced the latter to 0.335 s (single samples, not end-to-end UI
measurements). Snapshot reading stayed about 0.60 s. A separate exploration showed
album grouping still costs about 1.15 s in debug; it is outside this localized fix.
An intermediate packaged replay fixed the empty-state lie but still needed 2.61 s
after harness preparation to show tracks. Startup album relationship repair and
artwork maintenance began alongside the initial snapshot; defer them until the
first snapshot succeeds so their saves cannot restart that first read. This is
a scheduling change only; the maintenance itself is preserved.

Folder existence/locality checks also ran synchronously on the main actor at
launch. The new cancellable worker keeps that I/O off-main and rejects late results.

Focused tests passed (52 Swift Testing cases). The first full suite had one failure
in the unchanged gapless-preload test, which waits only 50 task yields; the optimized
build overlapped that run. All 343 Swift Testing cases passed. Repeat the full suite
without the competing compile: 313 XCTest (two expected optional-store skips) and
343 Swift Testing cases passed with zero failures. The optimized compile passed in
118.22 s; packaging initially rejected the symlink spelling /var. Repeating with
the canonical /private/var path packaged and verified signatures successfully in
1.51 s without recompiling or changing source.

## Decision Log

2026-09-15: measure the existing snapshot and projection pipeline before changing
it. Keep loading honest without treating a spinner alone as a performance fix.

## Context and Orientation

LibrarySnapshotStore builds immutable values on its model actor. MainView routes
library destinations to TrackTableProjectionView; its worker prepares filters,
sorting and display strings. Start from main e4bae889fdb7ab07f33bea0bcf27c362672eb94d.

## Plan of Work

Measure a cold read of the disposable catalog and its initial table projection.
Remove avoidable work at the identified stage, then keep revision-zero views in
loading state until a successful read or actionable failure. Add focused native
tests using existing injection seams; retain saved preferences and data behavior.

## Concrete Steps

Work in /Users/aji/project/songbird-public. Use the isolated source/home wrappers
under the external songbird-library-startup-6srth0hn work directory. Run focused
tests, ./check.sh quick -j 4 and optimized ./build.sh. Drive only the prepared
scripts/ai-usability profiles through scripts/usability/ui.

## Validation and Acceptance

Compare the same synthetic catalog before/after. Show loading instead of an empty
result before the first read; real empty/search-empty and failure/retry states
remain distinct. Verify the populated table twice and smoke navigation/Back.
Record uncovered whole-product/hardware outcomes honestly.

## Idempotence and Recovery

Keep before-images and installed-app backup. Do not read normal library/media or
print credentials. Preserve Last.fm application configuration during packaging.
Stop only the disposable app/broker PIDs. No database migration or data repair.

## Artifacts and Notes

Logs and fixture evidence are external; private user screenshot stays out of Git.
Current work pointer: /private/tmp/songbird-library-startup-current.json.

## Interfaces and Dependencies

Existing snapshot/projection interfaces, app startup scheduling and SwiftUI presentation. Audio and
vendor libraries remain unchanged, so audio concurrency/hardware tests are not
required unless scope changes.

## Outcomes & Retrospective

The localized startup changes are installed. Final runs 20260916T012159Z-26413
and 20260916T012319Z-26958 showed loading then all 10,000 tracks with no false
No Results state. Ready observations occurred 2.017 and 1.494 s after harness
preparation; these are not process-launch times or measurements of the owner's
library. The first final run also passed album navigation and narrow-window Back.
All five disposable apps/brokers were stopped. Reports retain incomplete broad
product coverage and no real-library, external-service or hardware claims.

Final quick suite: 313 XCTest (two expected skips), 343 Swift Testing, zero failures.
Final app compile/package passed in 6.07 s after the last scheduling change.
Installation verifies all 44 file/link entries, signatures, notices/resources and
Last.fm application configuration. Previous app backup:
/Users/aji/project/songbird-public-verification/installed-backups/Songbird-20260916T012350Z.app.
Evidence and receipt:
/Users/aji/project/songbird-public-verification/library-startup-20260915/.

PERF-STARTUP in NEXT_STEPS.md retains additional catalog/grouping optimization and
normal-library measurement. This pass removes avoidable work and false empty UI;
it does not establish instant startup for every library size/storage setup.
