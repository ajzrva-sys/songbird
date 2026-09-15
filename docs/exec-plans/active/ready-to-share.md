# Ready-to-share hobby build

## Purpose / Big Picture

Implement the owner's accepted 2026-09-15 plan: finish About/notices and transient
CD behavior, adopt the three reviewed audio libraries, and deliver a locally
prepared ad-hoc signed app plus corresponding source archive. Preserve permanent
Discogs imports, the original checkout and the normal library. No commit/upload.

## Progress

- [x] Owner explicitly authorized the complete plan, including library adoption.
- [x] Backed up the candidate and integrated the 18 prepared CD foundation paths
  after verifying every before/final hash. Existing review/remediator code retained.
- [x] Compact About and synchronize notices.
- [x] Complete CD surfaces, system metadata and long-rip recovery.
- [x] Adopt tested libraries and connect source validation.
- [x] Focused tests, combined Python/Swift/release/TSan checks; one additional
  disk-persistence regression passed afterward, without production code changes.
- [x] Disposable packaged smoke: About/all four notices offline, canned cover import,
  expiry, synthetic playback/pause and saved cover after network-denied restart.
- [x] Normalize/reconcile manifests and prepare app/source handoff.
- Post-seal offline rebuild: exact final archive and outcome are recorded externally
  in the companion RELEASE-RECEIPT.json to avoid self-referential archive hashes.

## Surprises & Discoveries

The earlier plan's D8–D14 and D22 status was stale: review code is integrated;
maintenance code is integrated with a later report-retention comment. Only the
18-path CD foundation was awaiting integration. The UI-fixture snapshot has no
completed handoff and must not be adopted wholesale.

## Decision Log

The accepted implementation plan supersedes the prior pause and unanswered S7
adoption request. Keep Songbird, permanent artwork/tags/reports and existing Undo.
Naming and privacy/contact decisions remain owner-nonblocking. No further rights
research or release-policy framework. Keep the current version and packaging.
Use the repository usability skill for the approved bounded disposable smoke check.

## Context and Orientation

The older release-licensing-remediation plan retains source receipts and the three
approved output hashes. Sources/OpticalDisc owns transient CD evidence/original
values; library snapshots and player surfaces must consume those values. Existing
mutation services own saved content. Sources/Views/AboutSongbirdView.swift already
has a document sheet. scripts/check-release-gates.py must invoke verify_component.

## Plan of Work

Finish the current implementations using existing value models and dependency
injection, with no schema migration. Adopt the recorded parent library outputs
using the reviewed installer/backup operation. Test focused behavior while editing;
then freeze inputs for a combined validation pass. Package/inspect a disposable
app, update release evidence, seal exact source files and verify an offline rebuild.
Deliver app/source archives, checksums and short instructions outside the candidate.

## Concrete Steps

Work in /Users/aji/project/songbird-public. Read current definitions before edits.
Use the 18-path CD ledger; never copy sibling workspaces wholesale. Use reviewed
rebuild installers with exact hashes and external backups. Run scripts/ai-usability
only with a disposable identity/profile and canned Discogs inputs. Build archives
from explicit manifests, excluding Git, builds, real libraries and local reports.

## Validation and Acceptance

Focused CD/presentation/rip/notice/source-gate tests; full Python and ./check.sh quick;
optimized build and scripts/test-audio-tsan.sh in isolated roots. Verify loaded
artwork expiry, permanent saved content after restart/offline use, system fallback,
long-rip recovery without audio loss, packaged document bytes and UI readability.
Use a bounded UI replay; record physical CD/AirPlay as untested if unavailable.
Require actual source/component/archive checks and three remaining technical gates.

## Idempotence and Recovery

Preserve external before-images and each old library. Recheck hashes before adopting
outputs. Do not overwrite unrelated user changes or the original checkout. Rebuild
only affected artifacts after fixes. No normal app/library operations.

## Artifacts and Notes

Implementation snapshots and logs use a new external songbird-ready run directory.
Final deliverables go under the sibling songbird-public-verification directory.

## Interfaces and Dependencies

Extend existing transient CD presentation values, per-instance test dependencies
and source-validation calls only. No persisted columns, public service changes,
new dependencies, version bump, Developer ID setup or notarization.

## Outcomes & Retrospective

The three technical gate records now pass using actual component, packaged notice
and system-display evidence. Preserved all permanent imports and Undo. Final source
instructions and archive manifests are sealed for local handoff; the external receipt
records the archive verification/rebuild after sealing. The owner subsequently confirmed physical-CD playback, ripping and eject.
AirPlay and the full UI matrix remain untested. No commit, public upload or normal-library operation.

## Owner-approved bird restoration — 2026-09-15

Human decision: after reviewing the artwork-specific research, the owner said
"ok well let's use it then. nobody is going to complain about this". Restore the
26 existing runtime PNGs from the preserved development checkout; retain the new
CD symbol. This supersedes the earlier instruction to replace all bird graphics.
It records accepted uncertainty, not a new rights grant.

- [x] Preserved the prior candidate payload and old app/source handoff externally.
- [x] Restored the PNGs, original Dock crops and Amber Bird label; recorded exact
      source hashes, notices and owner decision.
- [x] Run focused resource/theme/legal and publication tests, optimized build and
      a bounded disposable visual check of About, missing art and themed icons.
- [x] Produce and verify fresh matching archives/checksums; record the current
      offline app rebuild and identify earlier unchanged audio/dependency coverage.

Work receipt and backups: `/private/tmp/songbird-bird-restore-ope43jps`.
Use existing tests and packaging. No audio implementation, dependency bytes,
normal-library changes, public upload or new approval process is included.
