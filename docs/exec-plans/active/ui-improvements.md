# Songbird UI improvements

Approved by the owner on 2026-10-06. Implement all ten improvements in four
validated stages; source and disposable-profile verification only, no installed
app replacement. Preserve themes, action boundaries, private libraries, and
publication assets. The candidate's referenced `.agent/PLANS.md` is absent; this
plan follows the available ExecPlan workflow without importing excluded inputs.

## Progress

- [x] Stage 1: persistent scoped search, facet chips, actionable empty states.
- [x] Stage 2: local display controls, explicit album Play/Open affordances.
- [x] Stage 3: readable main player, guarded compact-queue controls and Undo.
- [x] Stage 4: Health freshness, explicit metadata edits, persistent Activity.
- [x] Focused checks, full quick, release compilation, applicable audio TSan.
- [x] Available isolated UI journeys across populated, empty, Health and large fixtures.
- [ ] Remaining keyboard/pointer, mixed-editor, import Activity and accessibility gates.

## Decisions

- Taller main player is approved; existing mini-player dimensions remain. Main
  height has its own preference, falling back to the old saved value without
  modifying it. Content/drag/Layout Studio all use a 72-point minimum.
- Clear All affects facets only; Clear Search affects only the query.
- Queue Undo restores exact occurrences/order only before later queue/playback
  changes. Never replace newer queue edits.
- Activity persists controlled summaries and filenames, never raw errors,
  paths, credentials, URLs, or provider responses. Limits: 500 terminal records,
  30 days, 2 MiB, 100 failure details per operation. Unfinished entries become
  Interrupted on restart. Corrupt history remains untouched until Clear History.
- Existing profile resolver isolates Activity storage; no SwiftData migration.
- Missing Git provenance is replaced with a current-source hash fallback
  in the disposable runner; privacy/parity gates remain enforced.

## Implementation and ownership

Library presentation: reuse snapshot/projection and search coordinators, maintain
keyboard selection guards, existing preferences, and card activation semantics.
Player/queue: increase main faceplate text/hit area; mutation-tracked Undo is
shared across queue views and preserves shuffle order.
Health/editor: present previous-result freshness independently; preserve untouched
mixed values and capture file-write policy at submission.
Activity: ordered atomic sidecar storage, in-memory live context, correlated
producer events and independently visible warnings while an operation runs.

## Validation

Focused behavioral tests cover each new presentation/action boundary, persistent
privacy/retention/failure handling, queue ordering/invalidation, and keyboard focus.
Run full quick, optimized compilation, applicable audio TSan. Recheck the recorded
Finder-notice baseline and distinguish inherited failures. Disposable UI uses only
prepare-only bundles, embedded isolated profiles and the existing privacy wrapper;
system pickers and external service paths remain intentionally unvisited.

## Discoveries and evidence

- Current source is the nested `songbird-public` candidate and has no Git metadata.
- Referenced plan standard and optional usability skill are absent. The runner's
  prepare-only path uses the present tester contracts and does not dispatch them.
- Baseline copy/hashes: `/private/tmp/songbird-ui-20261006/before` and
  `before-hashes.json`. Verification receipts will live in that scratch root.
- Cross-review fixed title modifier selection, per-file notice correlation,
  metadata error source preservation, main/mini height separation, and bounded
  Activity flushing on quit. Queue row playback gestures exclude child buttons.
- Final focused tests: 42 XCTest and 78 Swift Testing tests passed. Final full
  quick: 351 XCTest (two optional-store skips) and 394 Swift Testing tests passed.
  The documented Finder-notice failure did not reproduce. Logs: `focused-final.log`
  and `quick-health-fix.log` under the scratch evidence root. The latter full run
  includes the dashboard sizing repair discovered during UI validation.
- Python script suite: 116 cases, two optional vendor-rebuild skips; one legal
  input error because this candidate lacks `Package.resolved`. The new provenance
  tests and option/run-manifest shell regressions pass. The plan harness retains
  its six absent-standard/optional-skill issues; no excluded inputs were restored.
- Outer-sandbox audio/LocalAuthentication failures were rerun successfully with
  disposable profiles outside that sandbox. Copied release compiler modules
  retain the candidate's former path; runner honors a fresh Clang cache override.
- Applicable audio TSan passed 41 XCTest and 27 Swift Testing cases, with no
  reported races. Final optimized compilation passed in 79.53 seconds; isolated
  package parity and signatures passed. No installation was performed.
- Window-only evidence verified scoped search presence, hidden-browser chips,
  empty-state actions, distinct album Play/Open routing, queue Clear/Undo in both
  queue surfaces, Health freshness, and Activity retention after isolated relaunch.
  The 10,000-track/1,000-album fixture, Blue Monday at the top, Purple Rain at the
  bottom, and the supported 956-by-520 minimum with both panes were exercised.
- UI replay repaired album child accessibility labels and Health dashboard card
  heights after wrapped timestamps overlapped the next section. The current-source
  fingerprint is `c58426656f3da15f4332133f861ea7665b7c45664cc38e587380a2b9b60d8f25`.
- Keyboard/pointer injection did not reliably reach the prepared app. Dashboard
  AX snapshots failed JSON serialization, while screenshots and Health detail AX
  evidence worked. These gates remain unverified; no app-hang claim is made from
  transient broker/window-targeting gaps. Mixed editor interaction, compact row
  action routing, seeking, long titles and Activity during imports remain unvisited.
- Validation receipts and scoped before-image comparison live at
  `/private/tmp/songbird-ui-20261006/validation-receipt.json`. Each isolated run
  retains a schema-validated `artifacts/report.json`. The plan stays active for the
  remaining UI acceptance gates. See TESTING.md for commands and evidence limits.
