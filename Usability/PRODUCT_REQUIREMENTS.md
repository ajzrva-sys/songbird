# Songbird AI Usability Requirements

These are outcome requirements for an exploratory AI tester. They deliberately describe what a
person should be able to accomplish, not which controls, identifiers, or implementation types the
app currently has. The tester must discover the interface from screenshots and the macOS
accessibility tree.

## Product promise

Songbird should feel like a fast, understandable, native macOS music player. A person familiar
with ordinary Mac apps should be able to import or find music, browse it, play it, organize it,
correct its metadata and artwork, and recover from mistakes without learning Songbird-specific
rituals.

## Global usability requirements

1. **Immediate orientation**
   - On every window, a person can tell where they are, what is selected, and what useful action
     they can take next.
   - Primary content is not obscured, clipped, blank, or contradicted by stale loading/empty states.
   - Navigation does not unexpectedly discard an in-progress selection or operation.

2. **Native Mac interaction**
   - Single click, double click, Command-click, Shift-click, context click, Tab, arrow keys, Return,
     Escape, Space, and standard shortcuts behave consistently with comparable macOS controls.
   - Selection is visible without relying only on color and is exposed as selected through
     accessibility.
   - Destructive actions require clear confirmation and describe what is and is not deleted.

3. **Fast feedback**
   - Pointer and keyboard actions acknowledge within 100 ms.
   - Local navigation with already-loaded data displays useful content within 250 ms.
   - Longer work keeps the last useful content visible when possible, explains what is happening,
     and never presents a contradictory loading plus empty state.
   - No ordinary operation freezes input or repeatedly flashes between states.

4. **Discoverability and language**
   - Visible labels use concrete user language. Icons without text have an accessible name and
     help where their meaning is not obvious.
   - Related commands use the same wording in buttons, menus, context menus, and accessibility.
   - Disabled commands have a reason a person can infer from the current state.

5. **Accessible operation**
   - Every normal workflow is possible using only the keyboard and using VoiceOver semantics.
   - Reading/focus order follows visual order. Every actionable element has a meaningful role and
     name. Dynamic changes do not strand focus.
   - Important status, selection, errors, and progress are available without relying on color,
     animation, pointer hover, or visual inspection alone.

6. **Window and appearance resilience**
   - Main player, mini player, settings, editors, dialogs, and auxiliary windows remain usable at
     their minimum, default, and generously large sizes.
   - All themes preserve legibility, selection, focus, imagery, and contrast in their supported
     appearance. Preview controls accurately preview the result.

7. **Safe failure and recovery**
   - Empty libraries, missing files, unavailable volumes, corrupt metadata, offline services,
     denied permissions, and failed migrations explain the problem without destroying data.
   - A person can cancel, dismiss, retry, choose an alternative, or continue using unaffected parts
     of the app.
   - Reopening Songbird preserves valid library data and intentional preferences without recurring
     system prompts.

## Core user outcomes to explore every run

The tester must attempt these goals from the UI, choosing its own route:

1. Understand an empty library and reach a safe way to add music.
2. Find a known track, play it, pause it, seek, change volume, and understand playback state.
3. Browse tracks, albums, artists, genres, recent music, favorites, and play history.
4. Open an album and see its tracks without a perceptible avoidable delay.
5. Select adjacent and nonadjacent tracks and albums; perform and cancel a group action.
6. Add music to the queue, inspect order/history, reorder where supported, and clear upcoming items.
7. Create a playlist, add music, reorder it, rename it, and delete it without deleting audio files.
8. Search and filter, combine filters, clear them, and recover when no results match.
9. Favorite and unfavorite a track and an album, with one unambiguous control per state.
10. Open metadata, make and cancel an edit, locate a local file, and re-read metadata when allowed.
11. Identify missing artwork and start artwork search directly from the missing-artwork context.
12. Change a theme and Dock icon, confirm previews are visible, and verify the app remains readable.
13. Use menus, context menus, keyboard-only navigation, and the mini player for their normal tasks.
14. Resize every encountered window and inspect loading, empty, error, confirmation, and success
    states encountered during exploration.

## Exploratory mandate

The outcomes above are a minimum, not a closed feature list. During every run, the tester must:

- inventory all reachable windows, menus, navigation destinations, controls, and custom actions;
- explore at least one route or control not named in this document;
- flag actionable elements that cannot be understood from visible or accessible context;
- track which reachable states and actions were not exercised;
- suggest new outcome requirements when it discovers an important user capability;
- avoid declaring the overall app passed when substantial reachable UI remains unvisited.

## Evidence and verdict rules

- A pass requires an action trace plus before/after accessibility snapshots and screenshots.
- A failure requires a reproducible user-level sequence, expected outcome, observed outcome,
  severity, and evidence paths.
- Source-code inspection may diagnose a reproduced failure but cannot be used to declare UI success.
- Cosmetic preference is not a failure unless it harms comprehension, consistency, accessibility,
  task completion, or the product promise.
- Timing claims must be measured from the initiating action to the first correct useful state.

## Severity

- **P0:** data loss/corruption, unsafe destructive behavior, app unusable, or a core flow impossible.
- **P1:** core task fails, severe accessibility block, repeated system prompt, hang, or multi-second
  avoidable local response.
- **P2:** meaningful friction, misleading state, inconsistent native behavior, clipping, unreadable
  content, or inaccessible secondary action.
- **P3:** polish issue with a clear user impact but no blocked task.

