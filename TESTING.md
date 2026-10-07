# Candidate Testing and Validation

## Release build and push validation — 2026-10-06

- `swift package clean` removed generated caches carrying the pre-move path.
- `SONGBIRD_OFFLINE_DEPS=1 ./build.sh --no-reveal`: optimized build and packaging
  passed (155.23 seconds), with existing metadata deprecation and unused-result
  warnings. `codesign --verify --deep --strict --verbose=1 Songbird.app` passed.
- `./check.sh quick --disable-sandbox` used the existing disposable test scratch
  directory and a fresh `/private/tmp/songbird-release-push-20261006` profile;
  353 XCTest cases passed with two optional skips, plus 398 Swift Testing cases.
  Log: `/private/tmp/songbird-release-push-quick.log`.
- The temporary GitHub checkout at `/private/tmp/songbird-github-push-20261006`
  preserves upstream history, ignore rules, CI and Package.resolved. Release gate
  records and the resealed publication payload pass. App bundles/build caches
  are excluded from the source push. No installation, launch or new manual
  hardware/UI acceptance was performed.


## Artist Albums view — 2026-10-06

ArtistDetailView defaults to Albums and offers the previous track table as Tracks.
The artist album scope uses exact contributing track artists, retains complete
album groups, and has independent scroll anchors. The grid reuses its existing
search, Favorites, sort, size/spacing and shared Play/Open actions.

- Focused `AlbumGridInteractionTests|AlbumGroupingTests|LibraryNavigationCoordinatorTests|LibraryContentNavigationTests`:
  16 XCTest and 18 Swift Testing cases pass. New cases cover exact artist
  membership, compilation/multi-disc and edition preservation, projection cache
  invalidation, metadata changes and independent artist anchors.
- First full quick: 353 XCTest, two optional skips and one failure in the existing
  AudioDiagnosticsPoller stop test; all 398 Swift Testing cases pass. A focused
  poller rerun reproduced the queued callback after stop (6 polls rather than 5).
  The unchanged poller invalidates its Timer without cancelling already queued
  main-actor tasks. It has no artist-view dependency.
- Full quick after release compilation: 353 XCTest, two optional skips, zero
  failures; 398 Swift Testing cases in 53 suites pass. Earlier failure receipts
  remain in `quick.log` and `poller-rerun.log`; passing receipt is
  `quick-after-build.log`.

Before-images, scoped diff/hashes, exact invocation, test and prepare logs are in
`/private/tmp/songbird-artist-albums-20261006/`. Focused tests add the filter above
to `full-command.txt`. Full checks use macOS services outside the outer sandbox
with a disposable profile. Release preparation builds only the signed alternate
app for run `20261006T235833Z-27734`, package parity true, current-source SHA-256
`39f4b134bdeb52991be005a1f0db7a6e9b4d58c888b8bb6d215a89a749833262`.
The installed app and normal library are untouched.

Isolated run evidence is under
`.build/usability/runs/20261006T235833Z-27734/artifacts/`:

- Artists → The Skylarks opens Albums, showing only Northern Lights and its
  appearance on Signals: A Compilation. The grid exposes scoped Search,
  Favorites, Sort and View controls (`states/artist-albums-default.png`).
- Tracks shows the prior four-track table, including the compilation track;
  Albums restores the same two cards (`states/artist-tracks.png`,
  `states/artist-albums-roundtrip.png`).
- Open Northern Lights shows its three tracks; Back restores the same artist
  and Albums mode (`states/artist-album-open.png`, `states/artist-album-back.png`).
- Leaving the first artist in Tracks then opening 東京アンサンブル starts Albums
  with only its one album, without the prior artist's cards
  (`states/artist-second-default.png`).
- AXSetValue/AXConfirm changed the visible search-field value without reaching
  its shared binding; injected keyboard text also failed to arrive. This is a
  harness limitation, not evidence of a product search failure. Search empty/reset
  remains a manual UI gate; focused projection/filter checks pass.
- The bounded `artist-view-report.json` remains incomplete for the whole app.
  Keyboard/modifier/context routes, hover/Reduce Motion, themes/minimum windows,
  mini artwork activation and the broader application remain unvisited here.

Scoped whitespace checks pass. The document checker retains the same six missing
plan-standard/optional-skill file, directory and link issues. The isolated app and
broker are closed after the replay; evidence is preserved. No installation.

## Mini-player artwork return action — 2026-10-06

MiniPlayerView's shared 28-point track artwork is now a plain native Button
calling its existing `returnToFullPlayer()`. Modern and Glass share this artwork;
Classic and Strip have no artwork and retain their existing return controls.
The action already restores/opens the explicit main-player scene, closes Mini
Player and posts the shared window notification. It does not mutate playback.
The control is labeled Show Full Player and identified by
`player.switchToFullPlayer`.

- Focused `PlayerWindowConfigurationTests|LibraryNavigationCoordinatorTests`:
  eight XCTest and four Swift Testing cases passed. These cover adjacent window
  configuration/navigation boundaries, not activation of this new artwork button.
- Full quick: 351 XCTest cases, two optional skips, zero failures; 394 Swift
  Testing cases in 53 suites passed, outside the outer test sandbox.
- Scoped whitespace checks pass. The document checker retains its six existing
  missing plan-standard/optional-skill path issues.

Before-images, scoped diff/hashes, exact full invocation (`full-command.txt`),
`focused.log`, `quick.log` and `docs-check.log` are in
`/private/tmp/songbird-mini-artwork-20261006/`. The focused invocation adds the
filter above. The tested current tree includes the preceding album-grid changes.
No app was packaged, installed or launched. Actual artwork activation, full-window
restoration and playback continuity through that UI transition remain unverified
until the next disposable UI pass; source/adjacent tests do not establish them.

## Pointer-following album Play feedback — 2026-10-06

AlbumCardButtons.swift now tracks local pointer positions with continuous hover.
A clamped gradient center drives the surface light and accent rim, plus at most
four degrees of tilt on each axis. Tracking is attached after the fixed 44-point
frame/content shape; native Button action and accessibility labels remain.
Hover exit restores center. Keyboard focus uses centered feedback. Reduce Motion
locks the light at center and disables tilt, scaling and animation.

- Focused button/grid checks: four XCTest and 12 Swift Testing cases passed.
- Full quick: 351 XCTest cases, two optional skips, zero failures; 394 Swift
  Testing cases in 53 suites passed using macOS services outside the outer sandbox.
- Scoped whitespace checks pass. The control-document checker retains its six
  existing missing plan-standard/optional-skill path issues.

Before-images, scoped diff/hashes, exact full invocation (`full-command.txt`),
`focused.log`, `quick.log` and `docs-check.log` are in
`/private/tmp/songbird-pointer-hover-20261006/`. The focused invocation adds
`--filter 'AlbumCardButtonTests|AlbumGridInteractionTests'`.
No app was packaged, installed or launched. These source/action checks do not
verify the rendered pointer path, tilt or Reduce Motion; the next disposable
UI pass remains their visual acceptance gate.

## Source-only album Play hover feedback — 2026-10-06

AlbumCardButtons.swift adds a local native ButtonStyle: direct hover and keyboard
focus highlight the theme-accent rim/background; hover scales to 1.08 and pressed
scales to 0.94. The outer circular target stays 44 points. Reduce Motion fixes
scale at 1 and suppresses animations, with color feedback retained.

The current no-Git tree also includes the preceding outline/alignment fix.
Before-images, scoped diff/hashes and logs are in
`/private/tmp/songbird-play-hover-20261006/`.

- Focused `AlbumCardButtonTests|AlbumGridInteractionTests`: four XCTest and
  12 Swift Testing cases passed (`focused.log`), including native action routing
  and the hosted 44-point target.
- Full quick: 351 XCTest cases, two optional skips, zero failures; 394 Swift
  Testing cases in 53 suites passed (`quick.log`). The full run used macOS
  services outside the outer test sandbox.
- Scoped whitespace checks pass. The control-document checker retains the
  existing six missing plan-standard/optional-skill path issues.

Exact full invocation:

```sh
env SONGBIRD_OFFLINE_DEPS=1 \
  CFFIXED_USER_HOME=/private/tmp/songbird-play-hover-20261006/home \
  CLANG_MODULE_CACHE_PATH=/private/tmp/songbird-grid-visual-20261006/module-cache \
  SWIFT_MODULECACHE_PATH=/private/tmp/songbird-grid-visual-20261006/module-cache \
  SONGBIRD_UI_TEST_ROOT=/private/tmp/songbird-play-hover-20261006/profile \
  SONGBIRD_UI_TESTING=1 \
  ./check.sh quick --disable-sandbox \
  --scratch-path /private/tmp/songbird-ui-20261006/scratch \
  --cache-path /private/tmp/songbird-ui-20261006/cache \
  --config-path /private/tmp/songbird-ui-20261006/config -j 4
```

The focused run adds `--filter 'AlbumCardButtonTests|AlbumGridInteractionTests'`.
No app was packaged, installed or launched. Pointer hover/press animations and
rendered Reduce Motion behavior remain unverified pending the next disposable
UI pass; deterministic checks do not establish those visual outcomes.

## Source-only album grid visual fix — 2026-10-06

Tree: `/Volumes/projects/songbird-public/songbird-public`, without Git metadata.
The change is limited to AlbumGridItem's focus outline and AlbumGridLayout's
top alignment. Before-images and logs are in
`/private/tmp/songbird-grid-visual-20261006/`.

- Focused `AlbumCardButtonTests|AlbumGridInteractionTests`: four XCTest and
  12 Swift Testing cases passed. Log: `focused-cache.log`.
- Final full quick: 351 XCTest cases, two optional skips, zero failures;
  394 Swift Testing cases in 53 suites passed. Log: `quick-unrestricted.log`.
  The preceding restricted run (`quick.log`) aborted at macOS audio services
  and also recorded authentication/CD failures; it is not a passing gate.
- An initial manifest compile could not write the default module cache.
  Both module caches were redirected to the disposable directory for the
  successful runs; the original diagnostic remains in `focused.log`.
- Scoped whitespace checks pass. The control-document checker retains its six
  existing missing plan-standard/optional-skill path issues (`docs-check.log`).

Final full command, run outside the outer test sandbox:

```sh
env SONGBIRD_OFFLINE_DEPS=1 \
  CFFIXED_USER_HOME=/private/tmp/songbird-grid-visual-20261006/home \
  CLANG_MODULE_CACHE_PATH=/private/tmp/songbird-grid-visual-20261006/module-cache \
  SWIFT_MODULECACHE_PATH=/private/tmp/songbird-grid-visual-20261006/module-cache \
  SONGBIRD_UI_TEST_ROOT=/private/tmp/songbird-grid-visual-20261006/profile \
  SONGBIRD_UI_TESTING=1 \
  ./check.sh quick --disable-sandbox \
  --scratch-path /private/tmp/songbird-ui-20261006/scratch \
  --cache-path /private/tmp/songbird-ui-20261006/cache \
  --config-path /private/tmp/songbird-ui-20261006/config -j 4
```

Compilation and existing interaction checks do not establish rendered focus or
alignment acceptance. No disposable app or installed app was launched, and no
packaging or installation was performed, as requested by the owner. Visual
replay is pending for the next disposable UI pass.

## Installed follow-on: artwork mini-player button — 2026-10-06

The owner authorized installation after the source-only UI pass below, then
requested that small Now Playing artwork open Mini Player. The shared artwork
button posts the existing window action and is disabled during layout editing.
No playback or mini-player sizing behavior changed.

- Full quick: 351 XCTest cases (two optional skips, zero failures) and 394 Swift
  Testing cases passed. Release packaging completed in 86.49 seconds.
- Disposable standard run `20261006T212930Z-59452` verifies native button
  activation: the main window hides, Mini Player appears, and paused First Light
  remains at 0:05. Window-only snapshots are under its `artifacts/states/`.
  Physical pointer activation remains unverified: injected clicking produced
  no visible change. Keyboard, bottom placement and editing-state gates were
  not exercised in this bounded run. The isolated processes were stopped.
- The installed signed `/Applications/Songbird.app` matches all 44 release
  entries, modes and symlink targets. Executable SHA-256:
  `3353df7411f0ab70673d35b8f1f683e8a845bb0e627d335b378c5d0405f56bc2`.
  Source fingerprint:
  `8cbfd3bccf1cb2ee06457e3d72b7f84b0bd29259659bf3f2a87f659ce26252b0`.
- Rollbacks: `/Applications/Songbird-before-UI-20261006T212505Z.app` and
  `/Applications/Songbird-before-artwork-mini-20261006T213506Z.app`.
  Finder reveal succeeded; the installed app was not launched by the agent.
- Build-script syntax/help checks pass. Default successful builds now reveal
  the ordinary project-root `Songbird.app` in Finder; `--no-reveal` is available
  for unattended builds. Finder failure reports the ready app without failing
  packaging. `--open` retains its existing explicit launch behavior.

Receipts: `/private/tmp/songbird-ui-20261006/mini-click-install-receipt.json`,
`mini-click-package-manifest.json`, `mini-click-source-provenance.json`,
`mini-click-quick.log`, and `mini-click-build.log`. Earlier validation limitations
below are unchanged; installation does not close those visual gates.

## Ten UI improvements — 2026-10-06

Current tree: `/Volumes/projects/songbird-public/songbird-public`, without Git
metadata. The owner-approved [UI plan](docs/exec-plans/active/ui-improvements.md)
is implemented in source. This pass uses synthetic fixtures and disposable
profiles; it does not replace, restart or inspect the installed app or normal
library. Before-images, scoped changes and test receipts are retained under
`/private/tmp/songbird-ui-20261006/`.

Implemented behavior:

- Persistent search names the visible collection. Active facet chips remain
  visible when the browser is hidden; Clear All resets facets and Clear Search
  resets only the query. Empty library, filtered results, album favorites and
  playlist states expose their existing import, navigation or editing actions.
- Library View controls bind to the existing density, columns, artwork-size and
  spacing preferences. Album cards expose separate Play/Open actions and retain
  modifier selection and double-click playback.
- The main player has larger labels and a larger seek interaction area, with a
  separate main-player height preference and a 72-point minimum. Mini-player
  dimensions remain independent. Upcoming queue controls target occurrence IDs;
  Clear Remaining Tracks preserves the current entry and Undo restores exact
  occurrences/order only while its queue/playback revision still matches.
- Health displays current/checking/outdated/failed status separately from retained
  counts and timestamps. The editor preserves untouched mixed Favorite/Rating
  values, names Save Changes, and captures the catalog/file-tag write policy at
  submission. Favorite and Rating remain catalog-only; partial file writes retain
  distinct catalog and file counts.
- Activity stores controlled operation/source/status vocabulary, counts and
  filename-only categorized failures. Full messages remain in session memory.
  Atomic actor storage retains at most 500 terminal records for 30 days, bounded
  to 2 MiB and 100 failure details per operation. Progress persistence coalesces
  over two seconds; operation IDs isolate cancellation and suppress duplicate
  completion notices. Startup marks unfinished records Interrupted. Unreadable
  history is preserved until explicit Clear History. Quit prepares playback once
  and allows history flushing for at most two seconds. Warnings remain reachable
  during imports through the footer Activity panel.
- Disposable run manifests now use schema 3 and record a current, scoped
  source-tree fingerprint when Git is absent. No Git objects, excluded references
  or old reports were imported. Package parity and the privacy wrapper remain
  mandatory; the prepare-only route does not dispatch the missing optional skill.

Current verification:

- Focused Swift run: 42 XCTest and 78 Swift Testing cases passed, 120 total.
  `focused-final.log` covers the new presentation/action boundaries, metadata/file
  outcomes, Activity privacy/retention/recovery/cancellation/quit handling and
  queue occurrence/order/Undo behavior.
- Latest full quick passed: 351 XCTest cases with two optional-store skips and
  zero failures, plus 394 Swift Testing cases in 53 suites, 745 cases total.
  The historical Finder-notice assertions passed in this run. Earlier sandbox
  failures remain recorded separately; their audio/LocalAuthentication failures
  were rerun outside the outer sandbox using the disposable profile.
  Exact accepted invocation, from this candidate directory:

  ```sh
  SONGBIRD_OFFLINE_DEPS=1 \
  SONGBIRD_UI_TEST_ROOT=/private/tmp/songbird-ui-20261006/accepted-quick-profile \
  SONGBIRD_UI_TESTING=1 \
  ./check.sh quick --disable-sandbox \
    --scratch-path /private/tmp/songbird-ui-20261006/scratch \
    --cache-path /private/tmp/songbird-ui-20261006/cache \
    --config-path /private/tmp/songbird-ui-20261006/config -j 4
  ```

  Receipts: `quick-accepted.log` and the repeated current-source
  `quick-health-fix.log`, with the same totals. The preceding `quick-final.log`
  and earlier restricted/unrestricted attempts remain separate evidence.
- Thread Sanitizer: 41 XCTest and 27 Swift Testing cases passed, 68 total;
  `tsan.log`. Optimized compilation and disposable package parity passed through
  `SONGBIRD_OFFLINE_DEPS=1 CLANG_MODULE_CACHE_PATH=/private/tmp/songbird-ui-20261006/release-module-cache ./scripts/ai-usability --prepare-only --keep --fixture standard`.
  The runner uses `swift build -c release` with the supplied Clang cache override.
  The fresh cache avoids inherited compiler-module paths from the copied tree.
- Python suite: 116 cases, two optional vendor-rebuild skips, one legal-input
  error because `Package.resolved` is absent. This suite is not green. The two
  new provenance tests and option/run-manifest shell checks passed. The document
  harness retains six existing missing plan-standard/optional-skill file,
  directory and local-link issues; no excluded inputs were restored.
  Receipts: `python-unrestricted.log` and `harness.log`.

Bounded black-box evidence uses only the prepared alternate bundle/profile and
`scripts/usability/ui`, with window-only AX/screenshot capture. Standard run
`20261006T202901Z-28463` verified separate album Play/Open actions, album opening
without restarting playback, Back navigation, and a facet chip remaining visible
after hiding its browser. Queue Clear/Undo kept the current entry and restored
the exact upcoming order; four tracks totaled 16:58. Empty run
`20261006T203812Z-29884` verified Import Music and Top Played's Browse All Tracks
affordances. Its 800×600 empty-library window captured complete main content;
this check does not establish the wider minimum required with both side panes.
Evidence is in each run's `.build/usability/runs/<run>/artifacts`; the empty
session was stopped after verification.

Health run `20261006T204239Z-30895` observed Missing Files changing from Not
checked through Check Now to Current, with two findings and Results updated time.
Activity displayed one warning completed 12 of 12. The actual disposable sidecar
contains three categorized filename-only details, with no raw messages, paths,
URLs or provider responses; its verified copy is
`artifacts/activity-history.evidence.json`. Relaunching the same isolated bundle
and profile as PID 31853 retained that history and started with the Activity
panel collapsed. The app and broker were stopped afterward. These checks cover
completed history retention, not every interrupted/failed quit-recovery path.

Large repair run `20261006T204651Z-32035` passed optimized compilation in 79.53
seconds and package parity. Its schema-3 manifest records source-tree hash
`c58426656f3da15f4332133f861ea7665b7c45664cc38e587380a2b9b60d8f25`.
Window evidence shows 10,000 tracks totaling 910:50:00 and 1,000 albums, with
Search and View available. Native View, Player Bar and Feathers commands enabled
the compact Now Playing pane and changed Blue Monday/top to Purple Rain/bottom.
Explicit Play on Fixture Album 001 produced the compact queue, where upcoming
rows expose Play Next and Remove. Those two actions were inspected but their
actual routing was not exercised.

While paused, Clear Remaining Tracks preserved Fixture Track 02001 and reduced
the queue from eight tracks/41:20 to one track/2:50. Undo restored the seven
upcoming entries, Fixture Track 03001 through 09001, in exact order; the paused
and restored AX captures are byte-identical. With both side panes present, the
supported 956×520 minimum remained visually usable. An AX resize bypass to
800×600 clipped the compact pane below its documented 956-point minimum; that
capture is excluded from acceptance. Activity's Settings action opened
Appearance settings. A subsequent coordinate-based Library selection did not
change the selected settings pane, leaving import Activity unvisited. The app
and broker, PIDs 32553 and 32574, were stopped afterward.

The earlier Health Overview P2 timestamp overlap is fixed in the rebuilt replay:
`20261006T204651Z-32035/artifacts/states/health-dashboard-fixed.png` shows the
wrapped Results updated text clear of Consistency. The original screenshot and
failure remain in the Health report, with the finding marked fixed by this
replay. Dashboard AX serialization still failed at deep and shallow capture
depths, including the repair run; the resulting empty files are excluded from
evidence. Each of the five completed run artifact directories has a
schema-conforming `report.json` with verdict incomplete, explicit evidence and
unvisited journeys. The initial album accessibility-label finding is also fixed
by replay.

Keyboard injection was unavailable throughout these runs. Temporary broker busy
responses (exit 75) and missing-exact-window captures left observation gaps;
lightweight status confirmed the app was still running, so those failures are
not reported as an app hang or as measured latency. Keyboard/modifier and
double-click flows, seek pointer interaction, compact Play Next/Remove routing,
mixed-selection editing, import Activity with active warnings, long titles,
the complete theme/mini-player matrix, and dashboard AX acceptance remain open.
System pickers and external-service flows remain intentionally unvisited under
the privacy contract. The plan remains active pending its UI gates; these bounded
observations do not establish full UI, hardware or accessibility acceptance.

## Saved library artwork in audio files — 2026-10-05 follow-on

Tree: `/Volumes/projects/songbird-public`, still without Git metadata. Missing
Artwork Health now has **Save Library Artwork to Files…**, covering all current
tracks with a saved album cover, independently from missing catalog findings.
A fresh context reads each cover once per album and shares its Data across track
requests. The service deduplicates exact paths, rejects divergent per-path covers,
preserves existing pictures (including undecodable AV picture tags and empty
FLAC PICTURE blocks), and writes a neighboring copy through TagWriterService.
Recognized tags, sample rate, duration and exact saved JPEG/PNG bytes must pass
readback before commit. Current catalog path/album/cover and uncached original
file size/mtime/type are rechecked. Cancellation is checked again after the final
catalog await. Both artwork and the earlier metadata repair clear URL resource
caches before the final file guard; generated external-edit regressions cover
that cache hazard. Durable AV reads and the metadata-copy writer now throw/stop
on metadata-bag load failures rather than interpreting an error as missing tags;
normal reader defaults retain their prior recovery behavior.
Compact numeric/text iTunes YYYYMMDD dates expose the four-digit year; a generated
M4A regression checks that a missing-genre repair retains its full physical date.

The existing AV passthrough writer cannot export MP3. A generated MP3 explicitly
returns the unsupported-format failure and remains byte-identical. No new ID3
writer was added. JPEG/PNG FLAC/M4A are exercised; other writer formats and other
saved image formats have no new acceptance claim. Verification remains limited
to recognized metadata/image bytes and stream properties, not an encoded-audio
payload checksum or every opaque tag.

Evidence: `/private/tmp/songbird-file-artwork-20261005/`. Before-images and scoped
diff/source hashes are external; TagWriterService and the existing tag-test
before-images were reconstructed by reversing only this follow-on's localized
additions. All tests use generated media and disposable in-memory catalogs.

Focused environment: `SONGBIRD_OFFLINE_DEPS=1`,
`HOME=/private/tmp/songbird-file-artwork-20261005/home`, the same `CFFIXED_USER_HOME`,
`SONGBIRD_UI_TEST_ROOT=/private/tmp/songbird-file-artwork-20261005/profile`,
`SONGBIRD_UI_TESTING=1`.

- `./check.sh quick --disable-sandbox --scratch-path /private/tmp/songbird-file-tags-20261005/scratch -j 4 --filter 'LibraryFileArtworkRepairTests|LibraryFileTagRepairTests|MetadataReaderArtworkKeyTests|TagWriterServiceTests'`:
  final current-source run passed two XCTest and 25 Swift Testing tests in three
  suites. JPEG/PNG across actual FLAC/M4A copies, repeated fill-only writes,
  fresh whole-catalog scope without a published snapshot, changed catalog
  cover/path/album, failed readback/unreadable originals, concurrent file edits,
  post-catalog cancellation, path dedup/conflicting covers, undecodable AV picture
  presence, empty FLAC pictures, unsupported MP3 retention and physical compact-date
  retention all passed. Log: `focused-compact-date.log`.
- `./check.sh quick --disable-sandbox --scratch-path /private/tmp/songbird-file-tags-20261005/scratch -j 4`:
  final run used `HOME`/`CFFIXED_USER_HOME` at the new disposable
  `/private/tmp/songbird-file-artwork-20261005/final-home` and
  `SONGBIRD_UI_TEST_ROOT=/private/tmp/songbird-file-artwork-20261005/final-profile`,
  with the same offline/UI-test flags, outside the outer sandbox. It executed 342
  XCTest cases with two optional-store skips and only the same two failed
  assertions in unchanged `testShowInFinderReportsAnUnavailableSelectionWithoutRevealingIt`;
  all 365 Swift Testing tests passed in 47 suites. Full quick remains not green.
  Log: `quick-compact-date.log`. Earlier `quick.log` records the known outer-sandbox
  CoreAudio/LAContext failures and exception; `quick-final.log` records the
  preceding unsandboxed pass before compact-date normalization (364 Swift Testing
  tests, same Finder assertions). The test run was not repeated in the failing
  outer sandbox after its known restriction was identified.
- `./scripts/validate-agent-harness.sh docs/exec-plans/completed/file-tag-recovery.md`:
  retains the six missing plan-standard/usability-skill file, directory and local
  link issues in this candidate. Log: `harness.log`. No excluded inputs were
  imported to satisfy them.

No backend edit: audio TSan/hardware gates were not repeated. Source tests do not
access the normal library, install/launch the app, or establish black-box UI
usability. Root owns follow-on packaging and installation.

Final delivery verification: `SONGBIRD_OFFLINE_DEPS=1 ./build.sh
/private/tmp/songbird-tag-repair-20261005/release-final/Songbird.app` completed.
The built and installed bundles passed `codesign --verify --deep --strict`
outside the managed sandbox; all 44 installed file/symlink entries match the
package. `/Applications/Songbird.app` executable SHA-256 is
`5db11556ead0cb58f68ca8bba4f3dedd565f844739a75cf2482c42e3c6c03119`.
The original rollback is unchanged. No quit, relaunch, normal-profile UI or
hardware exercise was performed. Build/install receipts are private in the
dated album-art-repair workspace; this does not make the full suite green.

## Bulk file tag recovery and permanent Health repairs — 2026-10-05

Tree: `/Volumes/projects/songbird-public`, without Git metadata. Source adds
Health **Read File Tags** for missing metadata/artwork, reading at most four
unique paths concurrently and filling missing catalog values in a fresh context
after I/O. It does not run BPM analysis or alter the audio files. Existing catalog
choices and statistics remain. The AV reader now loads raw format-specific bags,
decodes NSNumber FourCC genre/year keys and binary track/disc pairs, recognizes
ID3 identifiers, and preserves tagged titles over a filename fallback.

Health **Save Checked Tags to Files** restricts durable edits to checked safe
missing-field proposals. A neighboring temporary copy is written through
TagWriterService, checked for the proposed value, unchanged other recognized
tags/artwork/sample rate/duration, then replaces the original only after passing.
Existing conflicting file values and changed catalog findings are skipped.
The unchanged half of a number/total pair is carried into writing. Filling an
artist can change the reader's derived album artist without creating an aart or
ALBUMARTIST tag; both physical formats have regressions for this case. Safe file
repair excludes titles, filename inference and consistency rewrites. Catalog
Undo is not offered as file Undo. This validation is not an encoded-audio payload
checksum or independent verification of every opaque tag; the existing writer
uses FLAC metadata updates or AVFoundation passthrough.

Plan: [file tag recovery](docs/exec-plans/completed/file-tag-recovery.md).
Before-images, scoped diff, exact source SHA-256 receipt and logs:
`/private/tmp/songbird-file-tags-20261005/`. The LibraryHealth.swift before-image
was reconstructed by reversing only the two added properties; other existing
changed source before-images were copied before editing.

Environment for both commands: `SONGBIRD_OFFLINE_DEPS=1`,
`HOME=/private/tmp/songbird-file-tags-20261005/home`, `CFFIXED_USER_HOME` set to
the same disposable home, `SONGBIRD_UI_TEST_ROOT=/private/tmp/songbird-file-tags-20261005/profile`,
and `SONGBIRD_UI_TESTING=1`.

- `./check.sh quick --disable-sandbox --scratch-path /private/tmp/songbird-file-tags-20261005/scratch -j 4 --filter 'LibraryFileTagRepairTests|MetadataReaderArtworkKeyTests|TagWriterServiceTests|TrackImporterSignatureTests|LibraryHealthProposalTests|LibraryHealthMutationTests'`:
  nine XCTest and 36 Swift Testing cases passed. Generated FLAC/M4A file writes,
  real raw iTunes keys, number-total retention, absent album-artist retention,
  stale catalog rejection, conflict/failed-copy preservation, unchanged file
  bytes during bulk artwork/metadata recovery and skipped BPM analysis executed.
  Log: `focused.log`.
- `./check.sh quick --disable-sandbox --scratch-path /private/tmp/songbird-file-tags-20261005/scratch -j 4`:
  final run executed 342 XCTest cases with two optional-store skips and two
  failed assertions in the unchanged
  `testShowInFinderReportsAnUnavailableSelectionWithoutRevealingIt`; all 356
  Swift Testing cases passed. Log: `quick-final.log`. Full suite is not green.
  Automatic review allowed this isolated run outside the outer sandbox after
  the sandboxed run could not initialize existing CoreAudio test components and
  failed existing audio/LAContext tests before crashing. The SwiftPM inner sandbox
  is disabled to avoid nested sandbox failure. Initial attempts also encountered
  the existing `.build` write restriction; the final run uses only the separate
  scratch directory. Earlier failures remain in `quick-sandboxed.log`.
- `./scripts/validate-agent-harness.sh docs/exec-plans/active/file-tag-recovery.md`:
  failed with six existing missing `.agent/PLANS.md` and usability-skill
  file/directory/local-link issues before the completed plan was moved. These
  unrelated harness inputs were not created or imported.

No backend edit: audio TSan/hardware tests were not repeated. No packaging,
installation, app launch, credentials, real library or media used by this source
pass. Black-box UI evidence remains unavailable because the privacy wrapper
requires absent Git metadata. Publication manifest remains the prior snapshot.

Follow-on app delivery on 2026-10-05: `SONGBIRD_OFFLINE_DEPS=1 ./build.sh
/private/tmp/songbird-tag-repair-20261005/Songbird.app` passed release compilation,
packaging and strict deep signature verification. The package was copied to
`/Applications/Songbird.app`, with installed executable SHA-256
`00d90ba436dbb6473e6ce587eef9703fef1f973707395a6acb64c5dfcaf0ec80`.
The previous app is retained at
`/Users/aji/Documents/Codex/2026-10-05/album-art-repair/rollback/Songbird-before-file-tags-20261005.app`.
Signature verification was repeated outside the managed sandbox because its
certificate trust check reports `CSSMERR_TP_NOT_TRUSTED` for both old and new
apps; the unrestricted verification passed. Build log and installation receipt
are in `/private/tmp/songbird-tag-repair-20261005/`. No app relaunch, normal-store
mutation, new black-box UI evidence or hardware acceptance is claimed.

## Missing artwork sorting and rescan progress — 2026-10-05

Current copy: `/Volumes/projects/songbird-public`, without Git metadata. Added
**Missing Album Art** to the album sort menu: missing covers first, then title,
artist and stable group ID. Search/Favorites continue to apply; cover updates
reorder the projected results. The missing-artwork rescan already selected only
uncovered canonical album groups; its initial counter incorrectly showed all
tracks. It now counts those album groups, reports per-album progress and enumerates
each shared directory once per run. Next rescan obtains fresh folder evidence.

Plan: [missing artwork sort](docs/exec-plans/active/missing-artwork-sort.md).
Source before-images, exact changed-source hashes, test/build logs, package receipt
and previous app: `/Volumes/projects/songbird-public-verification/artwork-20261005/`.

Test environment: `SONGBIRD_OFFLINE_DEPS=1`,
`SONGBIRD_UI_TEST_ROOT=/private/tmp/songbird-artwork-20261005/profile`,
`SONGBIRD_UI_TESTING=1`.

- `./check.sh quick -j 4 --filter 'AlbumGridInteractionTests|LibraryHealthProjectionStoreTests'`:
  final run passed 16 Swift Testing cases. Initial compilation required explicit
  returns after adding a multi-statement sort case; final build has no new diagnostics.
  Synthetic tests cover order, ties, search/favorites, cover refresh, excluded
  covered albums, relevant-album totals, directory reuse and next-run freshness.
- `./check.sh quick -j 4`: 342 XCTest cases, two optional-store skips, two failed
  assertions in the unchanged Finder-notice test from the prior divider pass;
  all 345 Swift Testing cases passed. Full suite remains not green.
- `SONGBIRD_OFFLINE_DEPS=1 ./build.sh /private/tmp/songbird-artwork-20261005/Songbird.app`:
  passed; release compilation 84.36 seconds, package strict signatures verified.
- Reinstalled `/Applications/Songbird.app`: all 44 file/link entries match the
  built package; signing identity matches the previous installation. Normal app
  restart is user-controlled.

No real-library, media or account checks. Black-box sort-menu and rescan visual
validation remain unavailable because the isolated runner requires missing Git
metadata (failure recorded in the prior divider pass). No backend changes;
audio TSan/hardware tests were not repeated. Publication manifest is a prior snapshot.


## Pane divider spacing — 2026-10-05

Tree: `/Volumes/projects/songbird-public` (no Git metadata). MainView and
PlayerWindowMetrics now reserve one point per pane divider instead of eight;
the invisible eight-point pointer target and keyboard slider remain. Existing
native rendering/layout tests check the narrow frame and updated pane budgets.
Before-images and logs: `/private/tmp/songbird-divider-20261005/`.

Commands used the environment `SONGBIRD_OFFLINE_DEPS=1`,
`SONGBIRD_UI_TEST_ROOT=/private/tmp/songbird-divider-20261005/profile`, and
`SONGBIRD_UI_TESTING=1`:

- `./check.sh quick -j 4 --filter 'ResizableDividerTests|UsabilityRemediationTests|PlayerWindowConfigurationTests'`:
  passed, three XCTest and 54 Swift Testing cases. An initial build was rejected
  because a test indentation edit overlapped compilation; the final retry passed.
- `./check.sh quick -j 4`: 342 XCTest cases, two optional-store skips and two
  failed assertions in `testShowInFinderReportsAnUnavailableSelectionWithoutRevealingIt`;
  all 343 Swift Testing cases passed. The Finder notice test also failed alone
  with `--filter LibraryItemActionHandlerTests.testShowInFinderReportsAnUnavailableSelectionWithoutRevealingIt`.
  That action handler was not edited. The full suite is not green.
- `./scripts/ai-usability --fixture standard --prepare-only`: exited 128 before
  launching; the runner requires Git metadata absent from this copy. Actual app
  appearance and pointer/keyboard resizing remain unverified.

Changed Swift SHA-256 values:

```text
b961b76ac4fc6d7bb3eb93e8890ec04b9de67a3c04e78c5bfbbfead692c10abc  Sources/Views/MainView.swift
18f93426d2ae859352e4fc33120f085cb4079ccaa14e2c46d999c2e8c8bcbf94  Sources/Utils/PlayerWindowMetrics.swift
3ba4642cf24ce0d61f4f9774bbacdfc111ff008d41d7352deb1ef3535aadf2ad  Tests/SongbirdTests/ResizableDividerTests.swift
8f26a6c3b02c8cd2bffb4fa157c9440c43ba0ed0e70356f4ddb1cd3b518dfed7  Tests/SongbirdTests/UsabilityRemediationTests.swift
```

Owner-requested build/reinstall followed: `SONGBIRD_OFFLINE_DEPS=1 ./build.sh
/private/tmp/songbird-divider-install-20261005/Songbird.app` passed (release
compilation 103.17 seconds), including strict signature verification. Reinstalled
`/Applications/Songbird.app`; all 44 file/link entries match the built package and
its designated requirement matches the previous installation. Backup, build log
and install receipt are retained under
`/Volumes/projects/songbird-public-verification/divider-20261005/`. The normal app
was not restarted. No backend changes; audio TSan and hardware gates were not run.
The referenced `.agent/PLANS.md` is also absent; this bounded styling correction
has no complex behavior ExecPlan. Publication manifest remains the prior snapshot.


## File location in table, metadata editor, and errors — 2026-09-18

Added a supported track-table column **Location** (hidden by default; enable via
column menu). Edit Metadata shows a read-only Location field (selectable path).
File-not-found playback errors always include the absolute path; Play Now surfaces
those errors instead of failing silently. Volume/permission resolver messages already
carried paths.

- Focused: `FileLocationPresentationTests`, `TrackTableColumnPrefsTests` label set.

## Embedded album art detection — 2026-09-18

m4a/MP3 covers often appear as `covr`/`cover`/APIC without the word “artwork”, and
already-imported albums only scanned for folder art when opened. MetadataReader now
recognizes those keys, loads artwork via multiple AVFoundation value paths, and only
accepts decodable image bytes. Opening an album without art re-reads folder files
first, then embedded tags.

- Focused: `MetadataReaderArtworkKeyTests`; folder-art suite still exercises discovery.
- UI re-open of a placeholder album with an embedded m4a cover was not run here.

## Play history in Queue section — 2026-09-18

Added a durable **History** destination under the sidebar Queue section. Qualified
plays append to `PlayHistoryStore` (UserDefaults log, newest first, capped at 500)
and the view also shows this session’s `PlaybackQueue` history. First open seeds
from library `lastPlayed` when the log is empty. Play Queue’s existing “Previously
Played” section is unchanged.

- Focused: `PlayHistoryStoreTests` + navigation destination round-trip including
  `.playHistory` — 14 tests, 0 failures.
- Full `./check.sh quick` / `swift test`: XCTest 336 (two expected optional-store
  skips), 0 failures; Swift Testing 343 in 45 suites, 0 failures.
- Command tree: `songbird-public/songbird-public`. UI open/play/close not run in
  this pass.

## Album list and playback position restore — 2026-09-18

Closing the main window (or relaunching) used to drop the user back to the top of
Recently Added and restart the current track from zero. The library now persists
navigation destination/path, album-grid scroll anchors (last opened or currently
playing album), and the seek offset. “Resume last track on launch” and “Remember
playback position” default on unless the user has already set them.

- Focused XCTest: `LibraryNavigationCoordinatorTests`, `PlaybackSettingsDefaultsTests`,
  `PlaybackEngineTests` — 20 tests, 0 failures.
- Full `./check.sh quick`: XCTest 330 (two expected optional-store skips), 0
  failures; Swift Testing 343 in 45 suites, 0 failures.
- Command tree: `songbird-public/songbird-public` at 2026-09-18. No app launch,
  packaging, audio TSan, or hardware matrix; UI restore behavior still needs a
  manual window close/reopen check against a real library.
- Files: `Sources/Utils/LibraryViewState.swift` (new), navigation coordinator,
  album grid scroll restore, `PlaybackEngine.persistLastTrack`, playback settings
  defaults.

## Edge-to-edge sidebar artwork correction — 2026-09-16

The owner clarified that the dark framing was the problem and requested the original
padding-free presentation. Removed the added padding, outline, rounded frame and
width cap. A square cover fills the sidebar width; navigation stays clipped above
it. In a window too short for that square plus 180 points of navigation, artwork
hides instead of shrinking inside dark margins. The prior padded design below is
superseded by this correction.

- Isolated quick suite passed: 324 XCTest (two expected optional-store skips),
  343 Swift Testing cases. Updated the existing constrained-layout expectations.
- Optimized build/package passed in 87.40 s. Disposable UI run
  20260916T082113Z-1564 verified the full image flush with both sidebar edges at
  normal and 520-point window heights, including scrolling to Play Queue.
- Installed /Applications/Songbird.app with all 44 bundle entries/signatures,
  resources/legal notices and Last.fm application configuration verified. Prior
  package: Songbird-20260916T082248Z.app in installed-backups. The new app's
  certificate-bound identity exactly matches the previous installation.
- Both disposable processes stopped. Normal app/library/credentials were not used;
  normal app restart is left to the owner. No Python/signing/backend changes, so
  those suites, audio TSan and hardware coverage were not repeated.

Evidence: `/Users/aji/project/songbird-public-verification/edge-artwork-20260916/`.
This is a bounded visual check, not a broad usability or real-account sign-in test.

## Sidebar artwork and stable local signing — 2026-09-16

See the [completed record](docs/exec-plans/completed/sidebar-artwork-signing.md).
Artwork now has a 160-point maximum, 12-point padding, a separate divider and a
clipped navigation region. Local packaging reuses an optional certificate identity;
unconfigured builds retain ad-hoc signing and configured errors stop packaging.

- Focused Swift: 50 passed. Full isolated quick suite: 324 XCTest (two optional
  store skips) and 343 Swift Testing cases passed. Python: 114 (two opt-in skips)
  passed. Usability runner option/manifest checks and shell syntax checks passed.
- Two different native test binaries signed with the same certificate wrote/read
  a synthetic item in a disposable Keychain with authentication UI disabled. An
  ad-hoc control was denied. No real credentials or normal library were accessed.
- Optimized build/package passed in 82.90 s. The installed designated requirement
  binds com.songbird.player to the persistent certificate, rather than a code hash.
  Private signing material is outside Git; system trust settings are unchanged.
- Certificate signatures exposed a library-parity assumption about signing times.
  The harness now verifies both signatures and compares designated requirements
  plus unsigned library bytes. Its zsh cleanup variable was also corrected.
- Disposable UI run 20260916T080048Z-62583 showed the padded full image at normal
  and 520-point heights, with navigation scrolling independently above it. Window
  scoped Pause resolved a global-selector ambiguity. Both test processes stopped.
- Installed /Applications/Songbird.app; signatures, all 44 package entries, legal
  resources and Last.fm application configuration verified. Prior app backup:
  Songbird-20260916T080259Z.app. Normal app was not restarted. Existing real Keychain
  items may need a final Always Allow grant per item for the new signing identity;
  this migration is left to the owner, without automated credential access.

Evidence: `/Users/aji/project/songbird-public-verification/sidebar-signing-20260916/`.
Bounded UI coverage only; no broad usability, physical-CD, AirPlay or real-account
claim. No audio/schema changes, so audio TSan and hardware tests were not repeated.

## Folder artwork discovery — 2026-09-16

See the [completed record](docs/exec-plans/completed/folder-artwork.md). Local lookup
recognizes cover/folder/front/album/artwork in common image formats, ignoring case,
with cover.jpg priority, immediate-folder scope and the existing 25 MB limit.
Opening an existing album fills a missing cover off-main, then rechecks membership
and current artwork before saving. Scans discover covers beside unchanged audio
without replacing tags; folders without artwork retain their scan fast path.

- Focused tests covered filename/case/priority, invalid candidates, new and unchanged
  imports, cancellation, concurrent cover/path changes, retained Undo and disk-store
  reopening after the original image was removed. The first full suite caught a
  resume-progress regression; preserving the no-cover fast path fixed it without
  weakening the existing test. Final quick suite: 324 XCTest (two optional-store
  skips), plus 343 Swift Testing cases; zero failures.
- Initial optimized build/package passed in 96.18 s. The first disposable UI check
  confirmed detail/grid/player refresh and cover retention after removing folder.jpg,
  but exposed stale sidebar artwork. ServicePaneView now consumes the current snapshot.
  The full suite passed again; final optimized package passed in 74.32 s.
- A fresh final 1,000-track UI check showed the discovered JPEG in the album header,
  grid, player and sidebar. Both disposable apps/brokers were stopped. This was bounded
  coverage, not a full usability or latency audit. Double-click starts playback;
  the accessible Open Album action was used for navigation.
- Installed `/Applications/Songbird.app`; all 44 bundle entries, signatures,
  resources/notices and Last.fm application configuration verify. Previous app backup:
  `Songbird-20260916T074422Z.app` under the verification directory's installed-backups.

Evidence: `/Users/aji/project/songbird-public-verification/folder-artwork-20260916/`.
Normal library/media were not accessed. No backend, schema or dependency changes;
Python, audio TSan, physical-CD and AirPlay coverage were not repeated.

## Compact Favorite column — 2026-09-16

Favorite uses a fixed 32-point width and a heart header with its accessible name
preserved. Older saved Favorite widths resolve to the compact size; other column
preferences are unchanged. Focused column tests: 13 passed. Isolated
`./check.sh quick -j 4`: 314 XCTest cases (two optional-store skips) and 343 Swift
Testing cases passed. Optimized `./build.sh` packaging passed in 80.69 seconds.

A bounded disposable 1,000-track UI check confirmed the 32-point header frame,
heart rendering and sort-indicator response. A deep window snapshot disambiguated
the header from row Favorite buttons before activation. This was a cosmetic change
check, not a broad usability pass; audio/hardware and Python checks were not repeated.
Installed `/Applications/Songbird.app`; all 44 bundle entries and signatures match,
and resources/notices and Last.fm application configuration are preserved. The prior
app is backed up as `Songbird-20260916T072239Z.app`. Evidence and the install receipt:
`/Users/aji/project/songbird-public-verification/favorite-column-20260916/`.
Disposable processes were stopped; normal library/media were not accessed.

## Initial library loading — 2026-09-15

See the [completed record](docs/exec-plans/completed/library-startup.md).
Folder existence/locality checks run on a worker with cancellation/generation
guards; startup maintenance waits for the first snapshot. Table preparation only
formats visible columns. An unread catalog shows Loading Library; failure offers
Retry and a successful empty read retains the ordinary empty-library presentation.

- Two fresh 10,000-track baselines reproduced No Results/zero tracks before data
  arrived. Two final replays showed loading then all tracks, without that false
  empty state. Album navigation, Now Playing and Back at 956 × 650 also passed.
- Focused suite: 52 Swift Testing cases passed. Final isolated quick suite:
  313 XCTest cases (two expected optional-store skips) and 343 Swift Testing cases,
  zero failures. The first full run hit the unchanged gapless-preload test's short
  yield-based wait while release compilation overlapped; reruns passed unchanged.
- External debug benchmark, same disposable 10,000-track store: default table
  preparation 0.411 → 0.335 s; initial snapshot about 0.60 s. These single samples
  measure specific stages, not real-library launch time. Album grouping still
  measured about 1.15 s in debug and remains a performance follow-up.
- Final UI observations became ready 2.017 and 1.494 s after harness preparation.
  Preparation itself takes time, so these are not process-launch measurements.
  An intermediate build took 2.605 s at the same observation stage before startup
  maintenance was deferred. No universal or instant-startup claim is made.
- Optimized compilation passed; an initial packaging attempt rejected the /var
  symlink spelling. Canonical /private/var packaging passed. The final app-only
  compile/package after maintenance scheduling changed passed in 6.07 s.
- Installed `/Applications/Songbird.app`; all 44 file/link entries, signatures,
  resources/notices and retained Last.fm application configuration verify. Backup:
  `/Users/aji/project/songbird-public-verification/installed-backups/Songbird-20260916T012350Z.app`.

Evidence, partial usability reports and receipts are retained at
`/Users/aji/project/songbird-public-verification/library-startup-20260915/`.
Normal library/media were not accessed. All disposable apps/brokers were stopped.
No audio/backend/schema/dependency change; Python, audio TSan, live network volumes,
and hardware coverage were not repeated. PERF-STARTUP retains remaining work.

## Back crash with constrained panes — 2026-09-15

See the [completed record](docs/exec-plans/completed/back-navigation-crash.md).
Back restored the sidebar with a fixed or sub-10-point resize range, causing
SwiftUI's stepped Slider initializer to trap. The divider now omits its slider
when resizing is impossible and caps its keyboard step at the available span.

- The reported main-thread crash matched two fresh disposable reproductions at
  956 × 650 points with Now Playing visible. A native rendering regression also
  crashed on the original code with `max stride must be positive`.
- Focused divider/navigation/window tests: eight XCTest plus four Swift Testing
  cases passed. Final isolated `./check.sh quick -j 4`: 313 XCTest cases (two
  expected optional-store skips), plus 339 Swift Testing cases; zero failures.
- Optimized build/package passed in 80.12 seconds. Two fresh 1,000-track UI
  replays survived the exact Back sequence. Additional checks covered widths
  960, 1090 and 1280 points, hiding Now Playing and reopening Albums.
- This is focused crash/window coverage, not a new navigation-latency benchmark
  or whole-product usability pass. Reports retain uncovered outcomes. Audio,
  database, dependencies and scripts did not change; audio TSan, Python and
  physical hardware coverage were not repeated.
- Installed `/Applications/Songbird.app`; all 44 bundle file/link entries match,
  signatures/resources/notices verify, and Last.fm application configuration is
  preserved. The previous app is retained at
  `/Users/aji/project/songbird-public-verification/installed-backups/Songbird-20260916T010456Z.app`.

Logs, partial UI reports, screenshots, installation receipt and checksums are in
`/Users/aji/project/songbird-public-verification/back-navigation-crash-20260915/`.
Only the exception and relevant stack frames were retained from the owner's crash
report. Disposable apps/brokers were stopped; the normal library was not accessed.
The previous wide-window Back check missed this constrained layout.

## Pause, album navigation and artwork reuse — 2026-09-15

See the [completed implementation record](docs/exec-plans/completed/pause-album-artwork.md).
Pause now silences/pauses the engine directly before saving position. Database
readers are constructed off-main, local album image bytes are shared across sizes,
and a detail view immediately requests any existing decoded cover as its preview.
Focused menu commands now observe focus in their own Commands type, preventing
window reconstruction from feeding a sustained SwiftUI update loop.

- Final isolated `./check.sh quick -j 4`: 310 XCTest cases (two optional-store
  skips), plus 339 Swift Testing cases in 44 suites; zero failures.
- Audio/artwork TSan: 37 XCTest and 27 Swift Testing cases, zero races/warnings.
  Backend/cache source was unchanged after this run.
- Python: 109 cases, two optional vendor-rebuild skips, zero failures. An initial
  concurrent packaging run temporarily removed Package.resolved; the final Python
  retry ran without that overlap and passed.
- Optimized build/package passed (80.79 seconds); final unchanged-source packaging
  passed again after UI preparation. Ad-hoc signatures and all 44 installed bundle
  entries match. Resources/notices and Last.fm application configuration are preserved.
- Two fresh 10,000-track disposable profiles reproduced the repaired Go to Album
  route: album header/cover reached their stable frame at 799.87 and 780.99 ms after
  Return. Neither replay sustained the prior layout freeze. These measurements
  include menu dismissal/transition and still exceed the 250 ms product target;
  PERF-ALBUM-250 in NEXT_STEPS.md retains that follow-up. An initial no-op frame
  capture with no open menu is explicitly excluded from timing evidence.
- Rendered checks also confirmed album Play (skipping a deliberately missing file),
  Pause switching back to Play, Command-A selecting all ten album rows, Back, and
  Command-F focusing Search All Tracks. Silent fixture playback verifies UI state,
  not audible stopping latency. Generic selector collisions were resolved with
  window-scoped actions; keyboard checks required the disposable app to be active.
- Table appearance/geometry and navigation-animation experiments failed to resolve
  the original stall and were reverted. Diagnostic logging was removed. Limited
  transition-time AttributeGraph warnings remain; no sustained input stall recurred.

The updated `/Applications/Songbird.app` is installed. The prior app is retained at
`/Users/aji/project/songbird-public-verification/installed-backups/Songbird-20260916T003847Z.app`.
Logs, schema-conforming partial UI reports, screenshots/frame evidence, checksums and
installation receipt are retained in
`/Users/aji/project/songbird-public-verification/pause-album-artwork-20260915/`.
All disposable app/broker processes were stopped. Normal library/media were not
accessed. Real-storage latency, audible output, AirPlay and broad UI coverage remain
unverified; physical CD coverage was not repeated.

## Playback responsiveness — 2026-09-15

See the [completed implementation record](docs/exec-plans/completed/playback-responsiveness.md).
Normal file opening/priming and seeking now run off-main; request generations keep
late results from changing playback or queue state. Retired decoder cleanup uses
an explicit worker-completion signal before closing file handles.

- Final isolated `./check.sh quick -j 4`: 310 XCTest cases (two optional-store skips)
  and 334 Swift Testing cases in 43 suites; zero failures.
- Final `./scripts/test-audio-tsan.sh`: 37 cases, zero warnings, including rapid
  native WAV/FLAC start/retirement. An earlier stress run detected two races in
  polling-based cleanup; the explicit completion fix passed the final reruns.
- Python suite: 109 cases, two optional vendor-rebuild skips, zero failures.
- Final optimized build/package: 97.55 seconds, ad-hoc signature verified. The
  pre-existing unused-result warning in TagWriterService remains unchanged.
- Controlled 250 ms source-factory delay: main-actor heartbeat 255.600042 ms with
  synchronous preparation versus 0.016042 ms with final asynchronous preparation.
  These are scheduling measurements from a synthetic seam, not live UI/NAS latency.
- `/Applications/Songbird.app` matches all 44 built bundle file/link entries; legal
  documents/resources match source and Last.fm application configuration is preserved.
  The prior installed app is backed up. Version remains 0.1.0; restart is user-controlled.

Logs, SHA-256 records and install receipt:
`/Users/aji/project/songbird-public-verification/playback-performance-20260915/`.
Tests used a disposable source copy/home/profile and committed/synthetic fixtures.
No real-library or media access. This pass did not measure audible onset, perform
rendered UI interaction, or repeat physical CD/AirPlay coverage.

## Last.fm browser sign-in — 2026-09-15

Settings now offers browser sign-in without username, password, API-key, or secret
fields. Returning to Songbird completes an approved token; Finish Sign In provides
an explicit retry. Unapproved tokens stay retryable, cancellation discards pending
state, and existing sessions remain compatible. Packaging accepts the maintainer's
application identity from environment variables or a private local plist.

- Focused authentication tests: 11 XCTest cases passed, including independent
  signature vectors, approval, pending/expired tokens, malformed replies, cancelled
  requests, failed credential writes, retained sessions, and sign-out. An earlier
  focused run also passed 12 credential migration/interaction Swift Testing cases.
- `./check.sh quick -j 4` in an isolated home/profile passed 296 XCTest cases
  (two expected optional-store skips) and 334 Swift Testing cases. Two additional
  cancellation/browser-launch tests were added afterward and passed in the final
  11-case focused run; production Swift code did not change after the full run.
- All 109 Python checks passed (two expected opt-in rebuild skips), including four
  new packaging tests for repeated local configuration and missing/partial inputs.
- Optimized compilation and configured ad-hoc packaging passed. Installed bundle
  signatures, all 44 file entries, resources, and packaged application configuration
  were verified. The previous installed app is preserved externally.
- Last.fm accepted a live signed `auth.getToken` request using the owner-created
  replacement registration. No user-account authorization or scrobble was submitted
  by this check. Real browser approval and the updated Settings UI remain manual
  acceptance; no automated visual-pass claim is made.
- Evidence is retained locally under
  `/Users/aji/project/songbird-public-verification/lastfm-sign-in-20260915/`.
  Credential values are excluded from source and evidence logs. No audio, library,
  hardware, or schema changes were made; audio TSan/hardware tests were not repeated.

## Track column context menu — 2026-09-15

The table-header context menu now lists the supported column checkboxes directly.
This removes the nested Columns item reported as non-opening on macOS 26.
Move Left/Right, playlist ordering, and one Reset Columns command are retained.
The Title column remains visible; existing column order and widths are preserved
when changing visibility.

- Native `NSHostingMenu` regression tests inspect the rendered menu items and invoke
  their actions to verify saved visibility, reopening, protected Title, and reset.
  These tests require macOS 14.4+; production deployment remains macOS 14+.
- Focused `TrackTableColumnMenuTests|TrackTableColumnPrefsTests`: 14 passed.
- `./check.sh quick -j 4`, with an isolated home and test profile: 287 XCTest cases
  (two optional-store skips) and 334 Swift Testing cases passed.
- Logs and the incomplete UI report are retained locally under
  `/Users/aji/project/songbird-public-verification/column-menu-fix-20260915/`.
- `SONGBIRD_OFFLINE_DEPS=1 ./build.sh /private/tmp/songbird-columns-d0xlfo7f/Songbird.app`
  passed, including optimized compilation, packaging, and signature verification.
- The disposable UI run reached album detail, but window-only captures did not
  expose the popup menu and the rebuilt run's accessibility inspector timed out.
  Visual menu behavior and twice-replayed UI verification remain unverified;
  native menu action tests are the current regression evidence. The probe timeout
  alone is not evidence of an application hang. Both disposable processes stopped.
- Audio TSan and physical-device tests are not repeated for this menu-only change.

## Owner-selected missing-artwork update, 2026-09-15

The owner supplied songbirdimage.png for the placeholder. The exact 1254×1254
image bytes replace missing-album-artwork.png; no runtime code or dependencies
changed. Focused resource/legal/thumbnail tests passed: nine XCTest cases and
four Swift Testing cases, no skips or failures. The disposable Albums grid
showed the selected illustration. The optimized build and packaging were refreshed.
The companion ready-to-share-0.1.0-cute-bird receipt binds this update's exact
images, bundled notices, source archive, signature and checksums. Earlier full
suites, audio concurrency and offline source rebuild remain prior evidence for
unchanged code; they were not repeated for this resource-only update.

## Current bird-artwork handoff, 2026-09-15

Restored the 26 existing runtime PNGs, original Dock crop settings and Amber Bird
label; updated provenance, notices and the existing owner-decision gate. No audio,
library or dependency implementation changed. Isolated frozen-source checks passed:

- Python: 105 tests, two opt-in vendor rebuild skips.
- Focused theme regression: 26 XCTest and three Swift Testing cases.
- Full quick: 285 XCTest cases (two optional-store skips), 334 Swift Testing cases
  in 43 suites; zero failures. Optimized compilation passed.
- Bounded disposable artwork/About/legal checks are in the companion UI report;
  unvisited UI remains uncovered. All 27 runtime image hashes and notice bytes are
  checked separately in the final package.
- Earlier audio TSan (25 cases) and full C dependency rebuild evidence is retained
  for unchanged code/inputs. The owner confirmed physical-CD play/rip/eject.
  AirPlay and the complete UI/device matrix remain untested.

The companion RELEASE-RECEIPT.json records exact final app/source archive hashes,
post-seal offline app/GRDB rebuild, signatures and the current/prior evidence split.
Local work: `/private/tmp/songbird-bird-restore-ope43jps`; handoff:
`/Users/aji/project/songbird-public-verification/ready-to-share-0.1.0-bird`.
The dated checkpoints below remain historical evidence for their described inputs.

## Baseline evidence, 2026-09-15

Validation ran from this copied project with a separate scratch directory and
isolated HOME, CFFIXED_USER_HOME, and SONGBIRD_UI_TEST_ROOT. No dependency checkout,
compiled object, or user-library database was copied from the original repository.

- `./check.sh quick --scratch-path <verification-dir>/scratch`: exit 0;
  180 XCTest cases, two optional-store-fixture skips, zero failures;
  284 Swift Testing cases in 40 suites, zero failures.
- `swift build -c release --scratch-path <verification-dir>/scratch`: exit 0.
- The optional current-store and V1-store migration rehearsals were skipped because
  no real-store fixture was supplied. Synthetic migration/recovery tests did execute.
- Expected corrupt-store recovery diagnostics appeared during the intentional
  invalid-database test. Compiler/debug-info diagnostics also appeared, including
  missing module-cache paths and the inherited unused-result warning at
  `Sources/Library/TagWriterService.swift:145`; the build is not warning-free.
- Documentation harness/local-link checks and all 19 generated fixture checksums
  passed. The exact payload and original-checkout preservation checks passed;
  a temporary unlisted-file negative probe was correctly rejected and removed.

Local logs and build results are in the sibling `songbird-public-verification`
directory, outside this publication payload. Specialized copied documents retain
historical evidence for their original trees only.

## Legal remediation checkpoint, 2026-09-15

Run from the candidate with isolated HOME/CFFIXED_USER_HOME, SONGBIRD_UI_TEST_ROOT,
SONGBIRD_UI_TESTING=1 and scratch outside the payload; optional real-store fixture
variables were unset. External logs are under /private/tmp/songbird-licensing.ia40aT/logs.

- `./check.sh quick --scratch-path "$RUN/scratch" --filter BPMDetectionTests`:
  six Swift Testing cases in one suite passed before product edits.
- `python3 -m unittest discover -s scripts/tests -p 'test_legal_*.py' -v`:
  10 cases passed; L1/L2 logs preserve meaningful assertion failures before fixes.
  During bootstrap GRDB_SOURCE identifies the verified clean 6.29.3 checkout's license.
- `./check.sh quick --scratch-path "$RUN/scratch" --filter LegalResourcesTests`:
  seven cases passed, including exact real SwiftPM/canonical text equality and lazy
  fallback/error boundaries; L4 logs record RED/GREEN assertions.
- `python3 scripts/legal_resources.py check . Sources/Resources/Legal`, followed by
  `python3 scripts/legal_resources.py stage . "$RUN/package-fixture/Contents/Resources/Legal"`
  and `python3 scripts/legal_resources.py check . "$RUN/package-fixture/Contents/Resources/Legal"`:
  passed. This stages legal files only; no app was packaged/signed or launched.
- `zsh -n scripts/package-songbird.sh`: passed; signing logic is unchanged.
- Full `./check.sh quick --scratch-path "$RUN/scratch"`: 187 XCTest cases, two
  expected optional-store-fixture skips, zero failures; 284 Swift Testing cases in
  40 suites passed. Intentional corrupt-store diagnostics remain expected.
- `swift build -c release --scratch-path "$RUN/scratch"`: passed; inherited
  TagWriterService.swift:145 unused-result warning remains.

These checks cover the integrated legal slice, not the independent artwork/publication
workspaces or final Discogs/source changes. Offline vendor rebuild, audio TSan,
rendered About/Discogs UI, signing and hardware acceptance were not run at this
checkpoint. L1–L5 do not modify audio behavior. Remaining plan acceptance stays open.

## Integrated legal/artwork/publication checkpoint, 2026-09-15

Same isolated harness as above; no candidate vendor replacement, app launch, signing,
real-store input or service token. Full quick and optimized compilation passed after
integration; logs are under the same external run's logs/ directory.

- Parent compiled `scripts/generate-original-artwork.swift` with
  `Sources/DockIconSupport/SongbirdArtworkCatalog.swift`, generated into two fresh
  directories and ran `diff -qr`: identical. All 27 generated images matched the
  integrated resources. Logs: artwork-parent-compile/first/second.log.
- Focused `ArtworkProvenanceTests|ThemeTests|ArtworkThumbnailServiceTests|LegalResourcesTests`
  passed (LA-integrated-focused.log).
- Full quick: 191 XCTest cases with two expected optional-store skips, no failures;
  284 Swift Testing cases in 40 suites passed (LAP-quick.log).
- Optimized compilation passed (LAP-release.log); inherited unused-result warning remains.
- `python3 -m unittest discover -s scripts/tests -p 'test_*.py' -v`: 75 cases passed
  (LAP-python.log), including 16 publication primitive, 37 phase, 11 gate and 11 legal
  input/resource cases. Parent added behavioral RED/GREEN for unreadable archive streams
  and complete nested notice delivery; child RED/GREEN receipts remain external.
- Current nested legal texts passed equality and staging in a new unsigned directory
  (package-fixture-nested). This does not claim a complete fresh signed package.
- `python3 scripts/check-release-gates.py .`: expected exit 1, six pending gates.
  Original-code authority and generated-art provenance bind actual evidence rows.
- `python3 scripts/verify-publication.py pre-seed .`: expected exit 1 because the
  preparation manifest is intentionally not resealed. Synthetic phase tests passed;
  this is not a verified complete publication payload.

Vendor source research is read-only evidence, not a rebuild. S3/S5/S6 vendor work
and D1–D7 are still isolated/unintegrated. Audio TSan, final source archive/offline
acceptance, rendered UI/hardware, signing and publication remain separate pending gates.

## S6 and Discogs-foundation checkpoint, 2026-09-15

S6's exact 177-file overlay and D1–D7's 25-file overlay were verified against their
before/final rows and integrated without overwriting other work. Parent independently
checked 169 upstream GRDB Git blobs and the sole upstream manifest adaptation.

- Current candidate full quick: 243 XCTest cases, two expected optional-store
  skips, no failures; 284 Swift Testing cases in 40 suites passed. Optimized build
  also passed (logs/core-final-quick.log and core-final-release.log).
- Current Python suite: 85 cases passed (logs/core-final-python.log), including
  nine S6 tests and the added exact Discogs non-affiliation notice regression.
  Its assertion RED is logs/discogs-notice-red.log; current source uses the supplied
  Vendor/GRDB.swift license, not the sibling read-only checkout.
- A 750-file exact current-source copy was frozen under the external run's
  core-offline-source before later documentation/proof updates. Parent ran
  run-core-validation.py offline and network-offline in that copy, each with fresh
  home/test-root/scratch. Both optimized builds passed; all 164 vendored GRDB Swift
  inputs and identical privacy resources were verified, with no dependency checkouts
  or repositories. The network-denied run's socket probe returned EPERM. See
  publication/grdb-offline-build-proof.json; actual executable receipts stay external.
- SwiftPM removed the unused Package.resolved in each local-only test copy run.
  The exact saved bytes were restored only there. The candidate's ordinary pin stayed
  unchanged; never run a restore trap over a concurrently edited source checkout.
- The actual scripts/test-audio-tsan.sh ran against the same frozen source: 25
  XCTest cases passed, no sanitizer report (core-tsan/build.log). The script does
  not forward scratch arguments; an external PATH wrapper invoked the actual Xcode
  Swift with a dedicated --scratch-path and -j 4. Product script was unchanged.

The outer macOS sandbox denied network for the dedicated build; SwiftPM's inner
sandbox was disabled only to avoid nested sandbox failure, not to remove that
network denial. No app/package/signing/UI, physical-CD/AirPlay/hardware, real-service
credential or library-maintenance operation ran. Existing C dylibs are unchanged,
so these runs are not controlled replacement-binary correspondence evidence.
S3/S5 and remaining D8–D24 work still require integration and new combined acceptance.

## Controlled C-vendor checkpoint, 2026-09-15

Candidate source/recipes were imported, preserving every official source byte and
notice. 125 world-writable archive modes were recorded and normalized to safe
0644/0755 modes. Parent actual rebuilds used the imported inventory and a private
CMake 4.4.3 tool installation; no global toolchain installation changed.

- With a fresh external SONGBIRD_REBUILD_RUN, `python3 -m unittest discover -s
  scripts/tests -p 'test_rebuild_*options.py' -v`: all 10 cases passed, including
  both real builds (logs/vendor-parent-build-tests.log). Without that explicit root,
  normal suite runs intentionally skip those two repeat-build cases.
- Exact parent outputs were copied only into a newly frozen current-source test
  directory, with before-byte backups. Candidate runtime binaries stayed unchanged.
- Focused BPM/native-backend/tag-writer plus test-only identity probe: 12 XCTest
  and 11 Swift Testing cases passed (vendor-regression-focused/run.log).
- Full quick: 244 XCTest cases including that one external-only identity probe,
  two expected optional-store skips; 284 Swift Testing cases passed. Runtime dyld
  paths and hashes matched the exact reviewed copies (vendor-regression-quick/run.log).
- Optimized compilation passed; actual audio TSan script passed 25 XCTest cases
  without a sanitizer report. The C dylibs are Release outputs, not separately
  TSan-instrumented libraries (vendor-regression-release/ and vendor-regression-tsan/).
- Parent compiled/ran the owned codec probe: native FLAC and Ogg FLAC each encoded
  and decoded 8192 stereo frames bit-exactly, with title metadata and zero decoder
  errors; actual loaded library paths were reported (logs/parent-codec-smoke.log).
- Exact new FLAC/ogg notices and retained CRC attribution passed legal input tests;
  canonical/resource equality remains enforced.

Selected parent build receipts are under vendor-parent-builds/ in the external run.
Public source-only summary is publication/vendor-build-proof.json. The S7 adoption
prompt was unanswered: no candidate or installed runtime library was replaced, and
no app/UI/hardware/signing/publication acceptance is implied by these checks.

## Commands

### Songbird name and privacy review decisions, 2026-09-15

The owner approved the Songbird name and waived the separate privacy/contact
review as a release prerequisite. Both gates are owner-nonblocking with separate
bound records. These are owner decisions; no independent trademark clearance or
completed privacy review is claimed. Runtime code and data are unchanged.

- The expanded combined-decision test first failed on the two previously pending
  gates, then all 17 focused gate tests passed. Tests reject changed/missing
  evidence, false review claims and attempts to waive unrelated requirements.
- Full Python suite: 102 cases, zero failures, two optional actual-vendor-rebuild
  skips. Fresh independent source copy and isolated home/test-root with local
  dependencies: `./check.sh quick --scratch-path <run>/scratch -j 4` passed 280
  XCTest cases (two optional-store skips) and 304 Swift Testing cases in 40 suites.
- Documentation/local links and all 1,667 frozen build-input hashes passed.
  SwiftPM removed the unused remote pin only in the disposable offline copy;
  restored/reverified after completion. Candidate pin bytes remained unchanged.
  Evidence: /private/tmp/songbird-release-decisions-w23a88wz/.
- LICENSE_SCOPE.md now describes the owner decisions; its original-code authority
  text is unchanged. Refreshed that file's bound evidence row and verified the
  actual gate checker against the current candidate.
- Actual checker accepts the four owner decisions and exits 1 for source
  correspondence, transient system-display policy and notice delivery.
- Vendor builds, optimized release, audio TSan and packaged UI/hardware acceptance
  are not rerun for this policy-only change. No installed-app access, provider
  communication, initial commit or public release is part of the checkpoint.

### Permanent metadata release decision checkpoint, 2026-09-15

The owner confirmed durable imported metadata, saved filenames, maintenance
reports and existing Undo. Both saved-artwork and metadata/report gates now accept
independently bound `owner-nonblocking` decisions; provider permission remains
unconfirmed. Changes are release-policy Python, records, documentation and one
Swift report-retention comment; runtime behavior and stored data are unchanged.

- The new combined-decision acceptance test first failed with the metadata gate
  still blocking. All 17 focused release-gate tests then passed, including separate
  decision binding, altered evidence, invalid records and unrelated gate rejection.
- `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/tests -p 'test_*.py' -v`:
  102 cases, zero failures, two optional actual-vendor-rebuild skips.
- Actual gate check accepts both owner decisions and exits 1 for five pending
  gates: brand, source correspondence, system display, notices and privacy/contact.
- Fresh independent source copy, isolated home/test-root, local dependencies and
  `./check.sh quick --scratch-path <run>/scratch -j 4`: 280 XCTest cases with two
  expected optional-store skips; 304 Swift Testing cases in 40 suites; zero failures.
  Documentation/local links and all 1,667 frozen build-input hashes passed. SwiftPM
  removed the unused remote pin only in the disposable copy; it was restored after
  the run and reverified. Candidate pin bytes never changed. Logs and checkpoint:
  /private/tmp/songbird-metadata-decision-tmo0yqdq/.
- Vendor rebuilds, optimized release, TSan and packaged UI/hardware acceptance
  are not rerun for this policy-only change. No publication, installed-app access,
  normal-library access or provider communication is part of this checkpoint.

### Permanent artwork release decision checkpoint, 2026-09-15

Only release-policy Python, gate/decision records and control documentation changed.
Permanent Discogs artwork became owner-nonblocking with provider permission
unconfirmed; the metadata/report gate was still pending at this earlier checkpoint.
Its later owner decision is recorded above. No app runtime behavior changed.

- A focused new acceptance test first failed because the artwork decision still
  blocked. All 16 tests in `test_release_gates.py` then passed, including rejected
  attempts to apply the exception to other gates and altered/missing decision evidence.
- `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/tests -p 'test_*.py' -v`:
  101 cases passed, with two optional actual-vendor-rebuild skips.
  Log: /private/tmp/songbird-owner-artwork-gates-python.log.
- Fresh independent source copy, isolated home/test-root, local dependencies and
  `./check.sh quick --scratch-path <run>/scratch -j 4`: 280 XCTest cases, two expected
  optional-store skips; 304 Swift Testing cases in 40 suites; zero failures.
  Input hashes and quick.log: /private/tmp/songbird-artwork-decision-wr2hvwje/.
- Documentation harness/local links passed. The actual release checker prints
  `Owner-nonblocking: discogs-permanent-artwork-policy`, then exits 1 for the six
  other pending gates. This is not overall release acceptance.
- Optimized build, vendor rebuilds, TSan and UI/hardware acceptance were not rerun:
  no Swift/C, dependency, audio, packaging or UI behavior changed. No provider
  message, commit, publication or installed-app operation occurred.

### Standard commands

- `swift build -c release`: compile optimized products without packaging or launching.
- `./check.sh quick`: full Swift package suite.
- `swift test --filter ThemeTests`: example focused suite; require a nonzero count.
- `./scripts/validate-agent-harness.sh [MARKDOWN ...]`: control structure/local links.
- `./scripts/test-audio-tsan.sh`: focused audio concurrency coverage.
- `./build.sh`: compiles, replaces the output app, packages and signs; NOT run here.

For isolated tests, create a new disposable home, a separate test-root directory,
and a SwiftPM scratch directory. Set HOME and CFFIXED_USER_HOME to the disposable
home, SONGBIRD_UI_TEST_ROOT to the separate test root, and SONGBIRD_UI_TESTING=1.
Do not direct tests at normal Application Support stores or supply real credentials.

## Validation gates

- Documentation: harness/local-link and whitespace checks.
- Behavior: focused tests followed by the full quick suite.
- Backend/audio: quick suite plus TSan and the audio hardware matrix before release.
- UI: focused tests plus disposable black-box evidence for usability claims.
- Data migration: synthetic fixtures and separately approved real-store rehearsals.

Signing, packaging, notarization, hardware/CD/AirPlay, real-service authentication,
UI interaction, fixture regeneration, and remote CI were not run for baseline
preparation. A build/test pass does not establish licensing or release readiness.

## Disposable usability

Read [the privacy contract](Usability/AI_TESTER.md), [product requirements](Usability/PRODUCT_REQUIREMENTS.md),
and `.agents/skills/songbird-usability/SKILL.md` before invoking the runner.
`./scripts/ai-usability audit --fixture standard --prepare-only --keep` prepares a
separately scoped disposable session; it packages/signs/launches and is not a
compile-only test. The returned run metadata identifies its exact app, broker,
profile, and artifact directory. Never target the normal app by its display name.
