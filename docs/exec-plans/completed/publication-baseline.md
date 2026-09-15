# Prepare a history-free publication candidate

## Purpose / Big Picture

Create a separately initialized local Git repository from an explicit file allowlist, preserving the original development checkout unchanged. This is the owner's requested first step after the licensing review, not clearance to publish, choose a license, replace artwork, or rewrite the original history. Keep the candidate uncommitted until those rights decisions are resolved so unresolved assets are not cemented into new ancestry.

## Progress

- [x] 2026-09-15T16:14Z: Rechecked source Git state, destination absence, available disk, manifest, packaging/test entry points, and toolchain.
- [x] 2026-09-15T16:20Z: Froze and copied 522 exact source entries, verifying bytes/modes and rejecting source links/collisions; excluded reference distributions and private operational material.
- [x] 2026-09-15T16:31Z: Prepared baseline-specific controls and a 537-file publication payload; empty local main has no commit, refs, indexed files, objects, remotes, or alternates.
- [x] 2026-09-15T16:31Z: Full quick suite and optimized release compilation passed. Payload hashes/modes, fixture checksums, pinned GRDB revision, new-root load paths, and source-preservation checks passed.
- [x] 2026-09-15T16:31Z: Recorded remaining rights/service/publication gates and completed outcomes. The owned unlisted-file probe was rejected, removed, and followed by a clean verification; ready to archive this plan.

## Surprises & Discoveries

- The source index still matches the old main commit, while the current product depends on many untracked files. A Git archive would omit necessary current code.
- The source's default status groups untracked directories; full-file inventory is required for exact manifest counts.
- The required documentation harness expects control files and a usability skill. Baseline-specific documentation will replace local execution histories rather than copying private library repair logs or old reference plans.
- Current product resources and aubio are needed for an unchanged build but still have unresolved distribution decisions. They may exist in this local candidate, not in an initial commit or public release yet.
- Fresh compilation emitted debug-info module-cache path warnings and the inherited unused-result warning at TagWriterService.swift:145, but both commands exited zero. The deliberately corrupt-store fixture logged recovery errors and passed; no normal library was used.

## Decision Log

- 2026-09-15: Owner requested the separate allowlisted baseline first. Preserve the source checkout and all its history, index, ignored build artifacts, and reference material.
- 2026-09-15: Use a separate local candidate directory named `songbird-public` and sibling local verification directory. No original `.git`, worktree link, alternates, remote, or historical objects may be copied.
- 2026-09-15: Copy all current package target source/tests/resources and required vendor source/notices/binaries; exclude unrelated application/reference trees, legacy root Resources/images, historical run reports/plans, agent session state, Python caches, and Synology maintenance scripts. List individual files and hashes before copying.
- 2026-09-15: Preserve application behavior and upstream notices. New candidate documentation and ignore rules are baseline-specific; original source files are not edited.

## Context and Orientation

`Package.swift` defines native SwiftPM targets and links bundled FLAC/ogg/aubio plus pinned GRDB.swift. `check.sh quick` forwards arguments to `swift test`. Packaging uses `scripts/package-songbird.sh` and normally signs; do not invoke it in this task. `publication/manifest.json` will be the explicit file inventory, not an inferred root-directory allowlist. `docs/LICENSING_REVIEW.md` records the prior development-checkout audit; any copied review is historical evidence, not a claim that this candidate contains the original history.

## Plan of Work

Freeze hashes and executable modes for selected regular files, reject symlinks/path traversal/collisions, and copy only those exact records. Create concise baseline-specific control docs so current commands and release limits remain navigable without importing personal logs. Initialize an empty local Git repository on main. Resolve the existing pinned dependency and validate entirely from the copied sources with isolated build/test paths. Compare original source hashes and Git state at completion; distinguish any external concurrent changes from this task's operations.

## Concrete Steps

1. Inventory current package inputs and selected docs/scripts in the preserved development checkout.
2. Write a frozen local copy manifest and preservation snapshot in the sibling verification directory.
3. Copy each manifest entry into the candidate; preserve bytes and executable permission bits without hard links or symlinks to the source.
4. Write candidate control docs and `.gitignore`; keep Package.resolved eligible for version control.
5. Run `git init --initial-branch=main` in the candidate only; do not stage, commit, or add a remote.
6. Run `./scripts/validate-agent-harness.sh`, `./check.sh quick --scratch-path <isolated-scratch>`, and `swift build -c release --scratch-path <isolated-scratch>` from the candidate. Set HOME/CFFIXED_USER_HOME and a separate SONGBIRD_UI_TEST_ROOT to disposable paths.
7. Verify exact candidate payload, copied-file hashes/modes, fixture checksums, no inherited refs/objects/remotes/alternates, and unchanged source checkout inputs/Git state.

## Validation and Acceptance

The candidate contains the complete unchanged product and tests, not references or prior Git history. Its selected file set is enumerated and hash-verified, and all copied package targets compile from the new root. Full quick tests and optimized release compilation must be exercised. Expected optional-fixture skips, failures, and environment gaps are recorded, never hidden by removing tests. No app launch, real-library access, hardware matrix, signing, packaging, or remote publication is claimed.

## Idempotence and Recovery

Never overwrite an existing unrelated destination. Copy fails if source hashes changed or destination entries collide. Verification is read-only and repeatable. All operational logs and isolated home/build artifacts remain outside the intended publication payload. The original checkout requires no restore step because it is never modified. If validation fails, preserve evidence and repair only a verified export omission; product failures require separately scoped work.

## Artifacts and Notes

Artifacts: explicit `publication/manifest.json`, `docs/PUBLICATION_BASELINE.md`, this plan, and the sibling local verification directory's `export-inputs.json`, `source-preservation.json`, `payload-verification.json`, `build-results.json`, `quick.log`, and `release.log`. The final payload contains 537 files: 519 unchanged copies, three adapted documentation files, 14 new documentation files, and the manifest itself. Its verifier rejects extra/missing/modified files and checks the empty Git boundary. The manifest is the sole self-hash exception.

## Interfaces and Dependencies

No Swift/C APIs, SwiftData schemas, package dependencies, fixtures, resources, or vendor binaries change. Baseline documentation and Git ignore rules differ intentionally. Existing aubio GPL, GRDB notice, artwork/branding, and Discogs policy gaps remain open.

## Outcomes & Retrospective

Baseline separation is complete. The copied project's quick suite passed 180 XCTest cases (two optional real-store fixture skips) and 284 Swift Testing cases in 40 suites, with zero failures; optimized compilation passed. All 19 generated audio fixture checksums passed. GRDB resolved to the unchanged lockfile revision, and the new executable's load commands contain candidate vendor paths rather than the old development root. Documentation harness/local-link validation passed, including the new baseline and licensing context.

The preserved original checkout still matches 532 checked file records plus its HEAD, branch, index, refs, staged diff, and complete untracked-aware status. This is scoped preservation evidence, not a forensic scan of every ignored original file. No original checkout file or Git state was changed by the task.

Remaining rights, notice/source delivery, API policy, privacy review, and initial-commit/push decisions are PUB-RIGHTS, PUB-API, and PUB-PUSH in the candidate NEXT_STEPS.md. Signing, packaging, app/UI launches, TSan, hardware, and remote CI were excluded and not run. The plan can be archived without claiming those gates passed.
