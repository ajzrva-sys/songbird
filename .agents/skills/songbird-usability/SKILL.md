---
name: songbird-usability
description: Run evidence-backed black-box usability exploration or safe repair of the Songbird macOS app. Use when asked to test overall app usage, discover UI problems beyond known regressions, audit workflows with AI, perform a usability sweep, validate accessibility/keyboard/native Mac behavior, or automatically repair reproduced usability failures.
---

# Songbird Usability Sweep

Exercise Songbird as a person would. Discover current UI from accessibility and screenshots; do not
substitute source inspection or existing unit tests for rendered behavior.

## Start

1. Read `Usability/PRODUCT_REQUIREMENTS.md` and `Usability/AI_TESTER.md` completely.
2. Preserve existing worktree changes and choose mode:
   - `audit`: observe and report; do not edit source.
   - `repair`: reproduce twice before changing code, then replay after each focused fix.
3. Check the execution context before starting anything:
   - If `SONGBIRD_USABILITY_PREPARED=1`, a disposable app and UI broker are already running. Read
     `$SONGBIRD_USABILITY_ARTIFACTS/run.json`, use `./scripts/usability/ui` directly, and continue at
     **Explore**. Never invoke `scripts/ai-usability` from a prepared session.
   - Otherwise run `./scripts/ai-usability <mode>` once. That runner prepares the isolated app and
     delegates exploration; do not launch a second copy yourself.
4. If the runner reports missing macOS permissions, stop and give its exact Accessibility/Screen
   Recording instructions. Never work around permissions.
5. Use only the prepared client and disposable profile. Never launch or drive the user's normal
   Songbird app.
6. Run `./scripts/usability/ui policy` once and obey it. Do not use full-app snapshots or activate
   filesystem, Finder, external-authentication, or external-search surfaces.

## Explore

1. Capture an initial screenshot and accessibility snapshot.
2. Inventory all windows, destinations, menus, controls, custom actions, selection containers, and
   disabled elements. Build a state/action graph as new UI appears.
3. Attempt every core outcome in `PRODUCT_REQUIREMENTS.md`; choose actions by human-visible or
   accessible meaning rather than source names.
4. Exercise at least one newly discovered capability not named in the requirements.
5. Cover pointer, keyboard, context menu, Command/Shift selection, cancellation, and window resizing.
6. Save before/after screenshot and accessibility evidence for each checkpoint. Measure response
   time through the probe output.
7. Treat unvisited reachable UI as uncovered, never as passed.
8. Stop after 60 UI actions or 10 minutes. Prioritize Songbird features; report the remainder.
9. Never run UI client commands concurrently. Do not classify probe timeout alone as an app hang.

## Diagnose and repair

In repair mode:

1. Reproduce a candidate failure twice from a fresh disposable fixture.
2. Inspect source only after evidence exists.
3. Do not automatically repair subjective design preferences, credentials/permissions, migrations,
   user-data behavior, or destructive behavior. Report those for review.
4. Make one minimal patch without overwriting unrelated changes.
5. Add a deterministic test or replay for the reproduced behavior when feasible.
6. Run focused tests, rebuild the isolated app, replay twice, then perform a broad smoke exploration.
7. Keep a fix only when the original evidence improves without reducing coverage.

## Report

Write the result using `Usability/report.schema.json`. Every finding needs a user-level reproduction,
expected and observed outcomes, severity, and artifact paths. Include:

- coverage for every core outcome;
- all evidence-backed findings;
- newly discovered product requirements;
- reachable states/actions that remain unvisited;
- whether any repair was verified twice.

Do not weaken requirements or alter the report schema to obtain a passing verdict.
