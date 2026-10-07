# Missing artwork sorting and local check progress

## Purpose and scope

Add Missing Album Art to the album grid sort menu, with missing covers first and
existing search/favorite scopes preserved. Artwork rescan must report only missing
album groups, never the entire library track count, and enumerate each relevant
folder once per check. Preserve cancellation, canonical grouping and catalog data.
No audio, vendor, schema, credentials, real-library or reference-tree changes.

## Progress

- [x] Read current sort/filter, health workers, views and focused tests.
- [x] Confirm rescan already selects missing-artwork groups; initial progress falsely counts all tracks.
- [x] Implement sorting, truthful album progress and per-run directory reuse.
- [x] Focused tests: 16 passed. Full quick: 342 XCTest with two optional skips
  and two failed assertions in the unchanged Finder-notice test; all 345 Swift
  Testing cases passed. This repeats the divider pass failure; suite is not green.
- [x] Release build/package passed (84.36 seconds); installed package has 44
  matching file/link entries and the same signing identity. Previous app retained.

## Decisions and discoveries

The copy has no Git metadata or .agent/PLANS.md. Use a self-contained bounded plan
with source before-images in /private/tmp/songbird-artwork-20261005/before.
The privacy wrapper cannot prepare a UI run without Git metadata. Do not initialize
Git or alter the normal library to work around it; visual UI validation remains open.
Missing Album Art is a sort: all albums remain, missing covers come first, title and
artist break ties and stable group ID breaks identical-label ties.

## Validation

Synthetic sorting tests cover mixed covers, equal-label ties, favorites/search and
projection updates when a cover is attached. Synthetic health checks cover relevant
album totals, covered-group exclusion and directory reuse. Run ./check.sh quick
with SONGBIRD_UI_TEST_ROOT pointing to a disposable root. Build via build.sh, verify
signatures and every installed file/link. Keep previous installation for recovery.
No backend edit: audio TSan/hardware checks are outside this change.

## Results

Implemented and installed. Evidence, changed-source hashes and previous app are
under /Volumes/projects/songbird-public-verification/artwork-20261005/. Exact
commands/counts and skipped gates are in TESTING.md. No performance measurement
or normal-library verification is claimed. Black-box validation remains open
because the isolated runner requires absent Git metadata; the full suite remains
not green due to the unchanged Finder-notice test.
