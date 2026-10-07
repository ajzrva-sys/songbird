# Artist pages with Albums and Tracks views

Owner request, 2026-10-06: artist pages should open with album covers like Albums;
retain the existing track table as an optional separate view. Source and isolated
verification only; do not install or use the normal library. The referenced
`.agent/PLANS.md` is absent; use the available plan workflow and tester contracts.

## Progress

- [x] Add artist-scoped album projection without losing compilation appearances.
- [x] Route artist pages to Albums by default and expose Tracks as a separate view.
- [x] Preserve scoped search, album actions, sorting and per-artist scroll anchors.
- [x] Run focused behavior checks and full quick; inspect the isolated artist UI.

## Decisions and ownership

- Match the same exact track-artist names as the current artist table. Include
  whole projected album groups containing those tracks; keep editions and
  multi-disc sets intact. Do not scan media or query SwiftData in view bodies.
- Reuse AlbumGridView and TrackTableView. Albums is the initial presentation;
  switching views does not start or replace playback.
- Keep existing album-card hover/focus changes and mini-player artwork action.
- All normal library, installed app, credentials and publication scope are outside
  this work. Before-images and receipts: `/private/tmp/songbird-artist-albums-20261006/`.

## Validation and remaining limits

Check artist membership (including compilations), projection cache/scope changes,
multi-disc preservation, search/favorites and distinct artist anchors. Run the
required Swift checks in a disposable profile. Use only the prepared alternate
app and privacy wrapper for UI screenshots/actions; no installation. Record exact
commands, results and any unavailable pointer/keyboard gates before handoff.

## Discoveries

- Focused behavior checks pass 16 XCTest and 18 Swift Testing cases.
- The first full quick and focused poller rerun exposed the unchanged audio
  polling cancellation race: invalidating its Timer leaves queued main-actor
  callbacks. The full quick after release compilation passes 353 XCTest (two
  optional skips) and 398 Swift Testing cases; preserve both earlier failures.
- Disposable run `20261006T235833Z-27734` has release package parity and source
  hash `39f4b134bdeb52991be005a1f0db7a6e9b4d58c888b8bb6d215a89a749833262`.
  Replay verifies Albums defaults for two artists, complete compilation inclusion,
  the optional Tracks table and album/Back navigation. Search injection did not
  reach its shared binding; empty/reset remains a manual gate with focused
  filtering checks passing. Broader audit, hover/focus, keyboard and mini artwork
  replay remain unvisited, explicitly recorded in the bounded report. No normal
  installation or library access.

## Outcome

The requested artist Albums default and optional Tracks view are implemented and
verified through the isolated native navigation path. Before-images, test logs,
exact invocations and scoped source hashes are in
`/private/tmp/songbird-artist-albums-20261006/`; UI evidence and the incomplete
whole-app audit report are under the prepared run's artifacts. This plan's source
and artist-route acceptance is complete; broader UI gates remain in TESTING.md.
