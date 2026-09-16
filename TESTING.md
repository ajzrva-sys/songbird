# Candidate Testing and Validation

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
