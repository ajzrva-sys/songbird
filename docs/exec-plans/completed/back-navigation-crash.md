# Back navigation at constrained pane widths

## Purpose / Big Picture

Fix the owner-reported Back crash while preserving the installed pause/artwork
performance improvements, normal library and original checkout.

## Progress

- [x] Read the crash stack from the installed 6400846 build.
- [x] Reproduce the constrained-width divider crash in two fresh disposable profiles.
- [x] Guard fixed ranges and cap the keyboard step; add native rendering regressions.
- [x] Focused/full quick tests, optimized build and two final UI replays.
- [x] Install with backup and retain local evidence.
- [x] Refresh manifest and verify publication payload for source handoff.

## Surprises & Discoveries

The main thread traps inside SwiftUI Slider Normalizing.init(min:max:stride:)
while evaluating ResizableDivider.body. The invisible accessibility/keyboard
slider uses a fixed 10-point step even when restoring the sidebar yields a
zero-width or smaller-than-step range. A disposable 956-point-wide album window with Now Playing open crashed on Back
with the same max-stride assertion. The native rendering regression also crashed
in a sub-10-point range. The prior large-window Back check missed
this constrained layout. No raw crash report or real-library data enters source.

## Decision Log

Keep a localized divider fix; retain navigation, pane-size preferences, drag and
keyboard accessibility. Do not change audio/database behavior. No audio TSan
rerun is required unless that scope changes.

## Context and Orientation

Sources/Views/MainView.swift contains Back, sidebar restoration and both pane
dividers. Sources/Utils/PlayerWindowMetrics.swift provides minimum widths and
budget allocation. Tests/SongbirdTests/PlayerWindowConfigurationTests.swift covers
layout policy. Start from main 64008462c574133ce05fef334459f79f20eb74f4.

## Plan of Work

Reproduce Back with narrow windows and both side panes. Render the divider's
actual SwiftUI control under equal/near-equal bounds in a focused regression.
Skip the slider for a fixed range and cap its step at the positive available span. Preserve
usable drag/keyboard increments and test minimum/default/wide window navigation.

## Concrete Steps

Work only in /Users/aji/project/songbird-public. Keep logs/backups in /private/tmp/songbird-back-crash-_gulo4o_.
Run isolated ./check.sh quick -j 4, then ./build.sh to the external app path.
Use scripts/ai-usability repair --prepare-only --keep and the prepared client;
never launch the user's normal app or access its library.

## Validation and Acceptance

The previous crash configuration must survive returning from album detail twice.
Native divider tests cover zero, sub-step and normal ranges and dynamic narrowing.
Focused/full tests and optimized packaging must pass. Record UI gaps as untested.

## Idempotence and Recovery

Keep source before-images and the installed app backup. Stop only disposable PIDs.
Use existing install verification for signatures, notices, resources and retained
Last.fm configuration; do not print credential values.

## Artifacts and Notes

Redacted crash stack: EXC_BREAKPOINT, main-thread Slider Normalizing assertion,
called by ResizableDivider.body. Crash occurred 2026-09-15 20:51 local time.

## Interfaces and Dependencies

No schema, dependency, saved-artwork, API or backend change planned.

## Outcomes & Retrospective

The fixed divider survived two fresh replays of the exact failing sequence. Native
rendering tests cover fixed/sub-step ranges and narrowing without changing saved
width preferences. Focused tests passed (8 XCTest, 4 Swift Testing), followed by
the full quick suite (313 XCTest with 2 expected skips; 339 Swift Testing cases,
zero failures). Optimized packaging passed in 80.12 seconds.

Baseline UI runs 20260916T005355Z-12266 and 20260916T005622Z-12964 both crashed.
Final runs 20260916T010020Z-13779 and 20260916T010327Z-14538 both survived Back at
956 × 650. The first also survived 960/1090/1280-point widths; the second hid
Now Playing and opened Albums successfully. Reports remain incomplete for broad
product coverage; selector lookup durations are not navigation benchmarks.

The verified app is installed at /Applications/Songbird.app. Backup:
/Users/aji/project/songbird-public-verification/installed-backups/Songbird-20260916T010456Z.app.
All 44 bundle entries match; signatures, notices/resources and retained Last.fm
configuration verify. No normal library/media was accessed. All disposable app
and broker processes were stopped. Evidence is retained under
/Users/aji/project/songbird-public-verification/back-navigation-crash-20260915/.

The earlier Back verification used a wider window. Future pane/navigation changes
need to exercise a fully constrained layout as well as ordinary window sizes.
