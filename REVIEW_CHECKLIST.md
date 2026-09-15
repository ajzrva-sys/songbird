# Review and Maintenance Checklist

## Change Review

- Scope: Does the diff touch only approved files and preserve unrelated dirty-worktree changes?
- Correctness: Is the user/system outcome observable, including failure, cancellation, and retry paths?
- Architecture: Does the change follow the owner/boundary map in `ARCHITECTURE.md`?
- Audio: Are real-time callbacks still bounded and are transitions backend-owned?
- Data: Are schema/store changes versioned, recoverable, and tested with disposable data?
- UI: Do keyboard, pointer, focus, selection, resizing, VoiceOver semantics, and error/loading states remain truthful?
- Security/privacy: Are credentials kept in Keychain and UI automation kept inside its disposable/privacy boundary?
- Parity: Is every reference claim explicitly scoped in `PARITY.md` and implemented without copied source?
- Dependencies: Is any dependency/config/entitlement change necessary, owned, and validated?
- Tests: Did focused tests run a nonzero count, followed by the proportionate checks in `TESTING.md`?
- Evidence: Are skipped/manual checks and exact blockers recorded? Are historical results still dated?
- Docs/state: Do control docs, active plan, task status, and current behavior agree?
- Legibility: Can the next agent locate the owner, invariant, test, and remaining unknown without a broad scan?

## Feedback Capture

Route each actionable review comment, repeated agent mistake, production bug, confusing doc, or architecture drift to the smallest durable home:

- Wrong/stale navigation or command -> update the owning doc and index/test truth.
- Reproducible behavior regression -> focused test, then code fix in a task/ExecPlan.
- Objective repeated rule -> proposed or implemented guardrail in `docs/QUALITY.md`.
- Small bounded follow-up -> `NEXT_STEPS.md` with allowed files and stop conditions.
- Complex/risky/multi-milestone follow-up -> active ExecPlan.
- Durable architectural choice -> ExecPlan Decision Log; promote to a dedicated decision record only if multiple future tasks need it.
- Unresolved current fact/conflict -> `CONTINUITY.md`.

Do not turn every preference into a rule. Require repository evidence and a practical verification path.

## Documentation Gardening Loop

Run after major work or when agents repeatedly rediscover repository structure:

1. Inspect `git status --short`; never clean or restore unrelated work.
2. Check `docs/.INDEX.md` and all control-doc relative targets.
3. Verify that documented commands still exist in the named scripts/manifests; run only safe, in-scope checks.
4. Compare `ARCHITECTURE.md` ownership/data flow with current package layout and entry points.
5. Reconcile `CONTINUITY.md` risks/unknowns and `NEXT_STEPS.md` status with current evidence.
6. Update active ExecPlans; archive completed ones only after outcomes and validation are recorded.
7. Revalidate dated audits/plans before retaining their claims as current.
8. Review `docs/QUALITY.md` gaps: promote repeated mistakes into low-noise tests/lints/scripts/CI proposals.
9. Remove duplication or stale claims with small targeted edits; do not broadly rewrite useful history.
10. Create bounded cleanup tasks for anything that cannot be verified within the pass.

## Plan/Task Closure

- Acceptance criteria are observable and satisfied.
- Actual commands/results and skipped gates are recorded.
- No task says Done while its linked ExecPlan remains active/incomplete.
- Completed plans include retrospective and follow-up IDs before moving to `completed/`.
- `CONTINUITY.md` contains only unresolved/current memory, not a duplicate changelog.
