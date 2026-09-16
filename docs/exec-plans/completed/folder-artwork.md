# Discover existing folder artwork

## Purpose / Big Picture

Recognize ordinary sibling covers such as folder.jpg and display them when an
already-imported album is opened. Retain saved covers and metadata.

## Progress

- [x] 2026-09-16: traced cover.jpg-only lookup and unchanged-file scan bypass.
- [x] 2026-09-16: implemented shared lookup, scan backfill and album-opening discovery.
- [x] 2026-09-16: focused tests passed: 16 XCTest and 15 Swift Testing cases.
- [x] 2026-09-16: final full quick suite passed: 324 XCTest (two optional-store skips) and 343 Swift Testing cases.
- [x] 2026-09-16: first optimized build and UI replay showed discovered art in
  detail, grid and player, retained after deleting the fixture image.
- [x] 2026-09-16: sidebar correction passed the full suite again, final optimized
  package (74.32 s), and a fresh disposable replay showing all four artwork surfaces.
- [x] 2026-09-16: installed the verified package with a retained backup. Source
  payload verification/publication receipts are stored with the external evidence.

## Surprises & Discoveries

Health already recognizes cover/folder/front/album/artwork in common image formats,
while import only recognizes cover.jpg. Both resume partitioning and preparation
skip unchanged audio without checking missing artwork.
The discovery task rechecks a fresh album after background reads, and late/cancelled
loads cannot overwrite a newer cover or changed membership. Disk-store reopening
after removing the original image still resolves the saved cover. Existing artwork
Undo remains available after unrelated automatic discovery.
The first full suite caught a resume-progress regression (unchanged audio without
any available cover was revisited). Partitioning now consults the per-folder cache
and retains the unchanged fast path when no cover is found. Folder images are
normalized once in that cache. Cover-only refresh never re-reads incomplete tags.
The first UI replay found the sidebar reading stale live-model artwork while the
detail/grid/player used refreshed snapshots. ServicePaneView now prefers its
existing LibrarySnapshotStore dependency for the selected/current track cover.

## Decision Log

- 2026-09-16: preserve cover.jpg priority; accept the Health filename conventions.
  Validate candidate images, remain in the immediate folder, and keep the 25 MB cap.
- Discover on album opening, off-main and only for missing artwork. Revalidate
  album membership and missing cover before saving; preserve existing Undo.
  No startup-wide scan, schema change, external lookup or normal-library automation.

## Context and Orientation

TrackImporter owns folder discovery. LibraryImportPipeline caches folder reads and
commits batches. LibraryItemActionHandler owns UI mutations; AlbumDetailView uses
immutable snapshots. Tests use disposable SwiftData containers and image fixtures.
Working tree started clean at 7106255 in /Users/aji/project/songbird-public.

## Plan of Work

Extend local cover discovery, then backfill missing covers even when audio is
unchanged. Add cancellable album-opening discovery through the action handler.
Test filename priority, unchanged imports, saved-cover preservation and snapshot
refresh. Verify a synthetic folder.jpg in the disposable UI and install the build.

## Concrete Steps

Run focused tests and ./check.sh quick -j 4 in the isolated source/home/profile.
Build with SONGBIRD_OFFLINE_DEPS=1 using ./build.sh and preserved Package.resolved.
Use scripts/ai-usability and its privacy wrapper for rendered evidence. Refresh
publication/manifest.json, run publication/release/harness checks, commit and push.

## Validation and Acceptance

folder.jpg loads without renaming or re-importing an existing album. New imports
and unchanged rescans also discover it. Saved artwork, metadata and Undo survive.
Invalid/missing files cause no destructive changes; file I/O stays off-main when
opening albums. No claim of physical-CD, AirPlay or normal-storage performance.

## Idempotence and Recovery

Fill only missing covers; recheck current membership after I/O. Cancel on navigation.
Preserve the previous installed app and retain all evidence outside the repository.

## Artifacts and Notes

Work: /private/tmp/songbird-folder-artwork-qb3oajkj.
Evidence: /Users/aji/project/songbird-public-verification/folder-artwork-20260916.

## Interfaces and Dependencies

No new dependency, database migration, audio/backend or vendor change. Existing
thumbnail invalidation and snapshot publication handle discovered covers.

## Outcomes & Retrospective

folder.jpg is discovered on import, unchanged scans and existing-album opening.
Saved art, tags and Undo survive; a disk-store reopen proves cover retention after
removing the original file. Cancellation/current-art/membership checks passed.
The sidebar now agrees with detail, grid and player after discovery. Final tests:
324 XCTest (two optional-store skips) and 343 Swift Testing cases, no failures.
Final app signature and 44 bundle entries match; Last.fm configuration is preserved.
Normal library/media and physical hardware were not accessed. This is bounded UI
verification with partial reports, not a broad usability or real-storage timing claim.
