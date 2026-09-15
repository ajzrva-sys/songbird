# Repository Agent Instructions

Songbird is a native macOS 14+ SwiftUI/SwiftData music player built with SwiftPM.
This is a separately prepared publication candidate, not the original development
checkout. Read docs/PUBLICATION_BASELINE.md before changing publication scope.

## Read first

1. docs/.INDEX.md
2. CONTINUITY.md
3. ARCHITECTURE.md
4. TESTING.md
5. NEXT_STEPS.md
6. .agent/PLANS.md
7. PARITY.md
8. docs/QUALITY.md and docs/GOLDEN_PRINCIPLES.md

## Scope and preservation

- Work only on the requested task or an approved task/ExecPlan.
- Preserve unrelated work. Do not stage, commit, push, or rewrite history unless asked.
- The original development checkout is separate; do not modify it from this candidate.
- Project-owned code is GPL-3.0-or-later. The owner approved retained bird artwork;
  see publication/artwork-decision.json. Do not reintroduce a naming/artwork release
  blocker or claim independently verified rights clearance.
- publication/manifest.json enumerates the preparation payload. It is not a rights grant.
- Do not import excluded reference trees, application bundles, private reports, or old Git objects.
- Keep Vendor/ binaries and upstream notices unchanged unless explicitly tasked.
- Do not hand-edit .build/ or packaged *.app contents.
- Do not read or publish credential files, real libraries, or private media.

## Native application invariants

- Cross-target declarations used by the executable must be public.
- Load SwiftPM resources with Bundle.module; packaged resource lookup must prefer
  the main bundle before evaluating the development fallback.
- Backend code owns gapless/crossfade timing, not UI timers.
- Audio render/decode callbacks must not allocate, block, log, access files,
  invoke UI/user callbacks, or destroy Swift objects.
- Migration failure must preserve the original store and surface recovery information.
- LibraryItemActionHandler is the shared mutation/action boundary.
- List backgrounds belong on their parent; hide content backgrounds where appropriate.
- UI automation uses only its disposable profile and privacy wrapper.
- Current source/tests and explicit product requirements outrank historical descriptions.

## Work and validation

Read definitions/usages and scoped diffs before editing. Prefer localized changes
and focused behavior tests. Use an ExecPlan for complex, risky, or multi-file
behavior changes; follow .agent/PLANS.md and store plans under docs/exec-plans/.
Run focused tests and ./check.sh quick for behavior changes. Backend work also
requires scripts/test-audio-tsan.sh. Release claims require the applicable manual
hardware matrix; UI usability claims require isolated black-box evidence.

Update control docs when facts change. Record the current tree, exact commands,
results, skipped gates, and unknowns. Do not convert inherited historical results
into current verification. Stop on missing permissions/hardware, conflicting
requirements, destructive operations, or rights questions outside the recorded owner decisions.
