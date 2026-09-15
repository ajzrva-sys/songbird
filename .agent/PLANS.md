# Executable Plan Standard

Use an ExecPlan for complex features, significant refactors, migrations, risky changes, multi-file behavior changes, unclear requirements, or work expected to span milestones. Small local tasks belong in `NEXT_STEPS.md`.

An ExecPlan is a living, self-contained document. A novice with only the current working tree and the plan must be able to continue without rescanning the repository or asking what to do next. Define repository-specific terms in plain language; name exact files, commands, tests, observable behavior, and acceptance criteria. Resolve ambiguity from repository evidence when possible and log unresolved judgment. Destructive or high-risk operations require explicit human approval.

Store active plans in `docs/exec-plans/active/`. Move them to `docs/exec-plans/completed/` only after outcomes and validation evidence are complete. Historical `.hermes/plans/` files are evidence, not active authority; port still-relevant work into this format instead of editing history in place.

Copy this structure for every plan:

# <Plan Title>

## Purpose / Big Picture

Explain what changes for the user, operator, developer, or system and what is out of scope.

## Progress

Use timestamped checkboxes. Update them as work proceeds; do not mark work complete before validation.

## Surprises & Discoveries

Record unexpected repository facts, failed assumptions, changed source, and new constraints with evidence paths.

## Decision Log

Record each decision, rationale, alternatives, evidence, and date. Mark human judgment explicitly.

## Context and Orientation

Name exact files, modules, existing tests, relevant current diffs, commands, and concepts. Explain boundaries a new contributor might miss.

## Plan of Work

Describe the edit sequence in prose. Explain dependencies between steps and why the order is safe.

## Concrete Steps

Give exact working directories, commands, and file operations. State expected observable output. Keep reference trees read-only and identify any command with side effects.

## Validation and Acceptance

Define user-visible or system-observable acceptance, focused tests, full checks, manual gates, and evidence storage. Compilation alone is insufficient for behavior changes.

## Idempotence and Recovery

Explain which steps are safe to repeat, how to inspect partial state, how to preserve user data and unrelated changes, and how to recover without destructive resets.

## Artifacts and Notes

Record concise outputs, screenshots, logs, fixture paths, or links. Do not paste large generated output into the plan.

## Interfaces and Dependencies

Name affected public APIs, SwiftData schemas, package targets, config files, external services, entitlements, hardware, and vendored dependencies. State compatibility obligations.

## Outcomes & Retrospective

Summarize final behavior, actual validation evidence, remaining risks, follow-up `NEXT_STEPS.md` IDs, and whether the plan can be archived.

Plan maintenance rules:

- Update Progress, Discoveries, and Decisions during implementation, not only at the end.
- If the working tree contradicts the plan, update the plan before continuing.
- Link one short `NEXT_STEPS.md` item to an ExecPlan; do not duplicate the plan there.
- Record skipped checks with the exact blocker.
- Never include secrets, user-library paths, or private UI evidence in a plan.
