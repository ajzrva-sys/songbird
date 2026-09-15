# Quality and Guardrails

Candidate context: this document preserves inherited guardrails and dated development-checkout findings. Historical task IDs, surveys, and reference-retention questions below are not active candidate tasks. Use [the baseline record](PUBLICATION_BASELINE.md), [candidate testing](../TESTING.md), and [candidate next steps](../NEXT_STEPS.md) for current state. The old reference trees and Git history were deliberately excluded.

## Quality Bar

- Preserve library data and unrelated working-tree changes.
- Keep changes localized to the owning subsystem in `ARCHITECTURE.md`.
- Prove behavior with focused tests and proportionate broader validation; compilation alone is not behavioral proof.
- Preserve real-time audio, migration recovery, disposable-test, target visibility, and resource-loading invariants.
- Treat native keyboard/pointer/accessibility behavior and truthful error/loading states as correctness.
- Keep control docs current, linked, evidence-backed, and explicit about skipped checks.
- Add no production dependency without an approved need and dependency-boundary review.

No repository-wide file-size limit, formatter, naming lint, or complexity threshold was found. Follow surrounding Swift naming and test organization; do not invent numeric style gates.

## Existing Mechanical Guardrails

| Guardrail | Evidence | What it proves / does not prove |
|---|---|---|
| Minimal macOS package CI | `.github/workflows/swift.yml` | Harness structure, package tests, and optimized compilation on the hosted toolchain after a pushed run; not packaging/signing, TSan, UI usability, external services, hardware, or release readiness. Remote run is pending. |
| Agent harness validator | `scripts/validate-agent-harness.sh` | Required control/usability files and directories, concise `AGENTS.md`, and existing local Markdown targets; not anchor correctness, prose accuracy, or external URLs. |
| Full Swift test target | `Package.swift`, `Tests/SongbirdTests/`, `./check.sh quick` | Broad deterministic logic/regression coverage; not hardware, signing, or full UI usability. |
| Focused audio TSan command | `scripts/test-audio-tsan.sh` | Races in named audio/queue tests; not every real device/timing path. |
| Atomic/ring-buffer tests | `AudioAtomicTests`, `NativeAudioBackendTests` | Queue/counter/transition mechanics under tests; not signal-quality release proof. |
| Versioned migration/recovery tests | migration/path/favorite/store tests | Known schema/recovery cases; optional V1 real-store fixture may be absent. |
| Disposable UI root validation | `MediaLibraryStore`, fixture/usability tests | Prevents unsafe test-root fallback. |
| Usability privacy wrapper | `scripts/usability/ui`, `Usability/AI_TESTER.md` | Blocks full snapshots, real filesystem/external-service actions, and concurrent client calls. |
| AX snapshot validator | `scripts/usability/validate-ax` | Unnamed enabled actions and loading/empty contradictions in one snapshot; not full accessibility conformance. |
| Packaging codesign verification | `scripts/package-songbird.sh` | Local bundle signatures/structure; not notarization/App Store acceptance or sandbox CD access. |
| Manual matrices | audio/CD/UI performance docs | Explicit release gates when actually completed; most relevant rows remain manual/pending. |

## Architecture and Testing Invariants

- App target imports the shared library, not the reverse.
- UI owns presentation and user intent; backend owns frame-accurate transitions.
- Persistence reads flow through snapshots/projections for large views; writes resolve models at controlled action boundaries.
- Migrations are versioned and recoverable; automation uses disposable stores.
- Every bug fix adds or updates the narrowest test seam that can reproduce it.
- A focused filter that runs zero tests is a failed validation attempt, not a pass.
- Historical results remain dated and never validate a newer tree.

## Documentation Invariants

- `AGENTS.md` stays under 200 lines and points to the current maps.
- `docs/.INDEX.md` links every control/source-of-truth document.
- `CONTINUITY.md` holds current state/unknowns, not a changelog.
- `NEXT_STEPS.md` tasks have allowed/forbidden files, acceptance, tests, budget, and stop conditions.
- Complex work has one active ExecPlan following `.agent/PLANS.md`.
- Reference claims are scoped in `PARITY.md`; reference source is never copied.
- Command status distinguishes repo-defined, historically passed, current passed, inferred, skipped, and blocked.

## Known Quality Gaps

- No formatter or Swift lint exists. Minimal package CI is defined locally but has not run remotely; the harness validator checks canonical local Markdown targets but intentionally does not validate anchors, prose truth, or external URLs.
- Audit high findings and strict-concurrency warnings need current-tree revalidation.
- Manual audio/CD/UI/accessibility release evidence is incomplete.
- Several large view files and duplicated patterns are reported by the dated audit, but no approved refactor plan exists.
- GRDB is linked without a surveyed direct import; intent is unknown.

## Proposed Future Guardrails

### Q-001: Harness structure and local-link validation

- Invariant: Required control files/directories exist, local Markdown targets resolve, and `AGENTS.md` stays concise.
- Evidence: The harness depends on cross-links; positive and disposable negative-path checks are recorded in `TESTING.md`.
- Why it matters: Agents should fail quickly on stale navigation instead of rescanning the tree.
- Enforcement: `scripts/validate-agent-harness.sh`; later call it from CI.
- Suggested failure message: `Agent harness invalid: <source> references missing <target>.`
- Priority: High
- Related task: `GRD-001` completed 2026-08-03.

### Q-002: Minimal macOS CI

- Invariant: The current package passes `swift test` and `swift build -c release` on an approved macOS toolchain.
- Evidence: Commands/scripts exist; no `.github/workflows/` entry was found.
- Why it matters: Local claims currently decay without branch-level enforcement.
- Enforcement: `.github/workflows/swift.yml`, one read-only `macos-26` job with no secrets/hardware/launch steps; remote run pending.
- Suggested failure message: `Songbird package validation failed; reproduce with ./check.sh quick or swift build -c release.`
- Priority: High
- Related task: `TST-001` completed locally 2026-08-03.

### Q-003: Current strict-concurrency diagnostic

- Invariant: Code does not accumulate diagnostics that become Swift 6 language-mode errors.
- Evidence: `CODE_AUDIT.md` reports five warning-enabled diagnostics but does not record the exact invocation.
- Why it matters: Future toolchain migration otherwise fails late and across unrelated files.
- Proposed enforcement: First verify and document the exact warning-enabled SwiftPM command; then add a non-mutating CI lane.
- Suggested failure message: `Strict-concurrency diagnostic added or regressed; fix the cited isolation/sendability site.`
- Priority: High
- Related task: `DOC-001` for current revalidation; create a separate implementation task after the command is verified.

### Q-004: Real-time callback forbidden-API scan

- Invariant: Render/decode callback regions contain no logging, blocking, file I/O, allocation, collection mutation, or user callbacks.
- Evidence: `AUDIO_ENGINE.md` and `RenderKernel` architecture make this safety-critical.
- Why it matters: These regressions can evade ordinary functional tests and cause nondeterministic audio failures.
- Proposed enforcement: Focused structural script plus code review, calibrated to named callback functions; never a broad naive grep gate.
- Suggested failure message: `Real-time callback uses forbidden operation <symbol>; move work to decoder/control side.`
- Priority: High
- Related task: Needs a scoped ExecPlan because false positives and callback boundaries require design.

### Q-005: Validation evidence stamps

- Invariant: Checked release/performance claims identify date, tree/ref, command/method, and result.
- Evidence: `docs/UI_PERFORMANCE_ACCEPTANCE.md` has checked automation with no attached run record.
- Why it matters: Agents otherwise treat stale checkboxes as current truth.
- Proposed enforcement: Review checklist now; docs schema/check later if repetition justifies it.
- Suggested failure message: `Checked validation claim lacks dated command or artifact evidence.`
- Priority: Medium
- Related task: `DOC-002`

### Q-006: Dependency-use audit

- Invariant: Every production dependency has a named owner/use or an explicit retained-purpose note.
- Evidence: GRDB is linked by `Package.swift`, but no direct surveyed Swift import was found.
- Why it matters: Unused dependencies add resolution, supply-chain, and agent-confusion cost.
- Proposed enforcement: Periodic review script/report; removal requires separate approval and full validation.
- Suggested failure message: `Dependency <name> has no verified production import or documented retained purpose.`
- Priority: Medium
- Related task: Needs human confirmation before a removal task.

### Q-007: Reference-tree write protection

- Invariant: Product tasks do not modify or copy from reference trees.
- Evidence: References are large, differently licensed, and the worktree already contains mass deletions.
- Why it matters: Accidental formatting/staging can create enormous diffs or licensing problems.
- Proposed enforcement: CI diff-path check or pre-commit review after retention policy is decided.
- Suggested failure message: `Reference path changed outside an approved reference-maintenance task.`
- Priority: Medium
- Related task: `PAR-001`

## Guardrail Adoption Rule

Add a mechanical guardrail only after a real invariant and low-noise enforcement method are identified. A noisy or easily bypassed check reduces agent legibility. Record exceptions in the check itself and link the rule back here.
