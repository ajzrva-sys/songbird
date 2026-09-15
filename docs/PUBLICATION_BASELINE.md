# History-free publication candidate

Prepared locally on 2026-09-15 at the owner's request. This completes repository
separation first; it does not resolve application licensing or authorize publication.

This document and publication/manifest.json preserve the original preparation
snapshot. Later approved PUB-REMEDIATION work intentionally changes legal resources,
artwork and publication controls; the preparation manifest is not yet resealed.
Current state is in CONTINUITY.md and NEXT_STEPS.md. Historical copied-asset and
test-count statements below are not claims about the remediated current tree.

## Included

An explicit pre-copy manifest selected 522 regular files (38,413,599 bytes) from
the current development tree: all package source/test/tool targets, synthetic audio
fixtures, current resources, required vendor binaries/source/notices, pinned package
files, build/test/usability scripts, configuration, selected technical documents,
and the fictional-library README screenshots. Every copied file's SHA-256 and mode
was verified. Product inputs were not modified.

The final publication/manifest.json enumerates the candidate's 537-file intended
payload, including baseline-specific documentation and ignore rules. It records
which original files were copied unchanged and which documentation was adapted.
The manifest itself is listed as the only self-hash exception.

## Excluded

- Original .git directory, refs, objects, checkpoint trees, remotes, worktree links,
  Git alternates, and historical commits.
- Swinsian, Cog, Museeks, and Nightingale reference/application distributions,
  including the nested untracked Nightingale binaries.
- Legacy root Resources/ and loose reference images; songbird-images/ and carousel/.
- .build/, .swiftpm/, object/Python caches, agent session state, and usability run reports.
- Synology maintenance scripts and historical real-library/operational logs/plans.

The original development checkout was not reset, cleaned, staged, or rewritten.
Verification compares its copied inputs and control documents plus HEAD, branch,
index, refs, staged diff, and complete untracked-aware Git status to the pre-copy
snapshot. These checks establish preservation of the checked scope, not a forensic
hash of every ignored file in the original checkout.

## Git boundary

A new local repository was initialized on main without cloning or copying Git
metadata. It intentionally has no initial commit or remote. Keep it uncommitted
until the remaining asset/license decisions are resolved; otherwise an initial
commit could put unresolved artwork into the new history again.

Package.resolved is retained and eligible for version control. New ignore rules
exclude build/session/credential/reference outputs without ignoring vendor dylibs.
The manifest is a snapshot boundary: deliberate future changes require review and
an updated manifest before initial publication, not blind re-export from the old tree.

## Verified product execution

- Full quick suite passed: 180 XCTest cases, two expected optional-store-fixture
  skips, zero failures; 284 Swift Testing cases in 40 suites, zero failures.
- Optimized release build passed from the copied sources and separately resolved
  pinned GRDB package. No old .build or dependency checkout was imported.
- Validation used an isolated home/test root and a scratch directory outside the
  intended publication payload. No normal app/library was launched.
- Build diagnostics remain, including debug-info module-cache path warnings.
  Passing compilation is not a warning-free or hardware-release claim.
- All 19 generated audio fixture checksums and the documentation harness/local links
  passed. The payload verifier rejected an owned unlisted-file probe, then passed
  again after its removal. Candidate Git objects, refs, indexed files, remotes, and
  alternates are absent. Original source/control hashes and checked Git state match.

Exact local commands/logs and the source preservation snapshot are in the sibling
songbird-public-verification directory, not in this public candidate.

## Remaining gates

Aubio/application licensing, full GPL/GRDB notice delivery, corresponding-source
release correspondence, current artwork and Songbird-branding rights, Discogs
attribution/freshness/persistent-content policy, and final privacy/contact-metadata
review remain open. Current app assets/vendor dependencies are retained locally
for build fidelity, not certified for redistribution. See [licensing review](LICENSING_REVIEW.md).

No initial commit, push, remote CI run, signing, packaging, app launch, TSan,
hardware or full UI acceptance was performed by this baseline-preparation task.
