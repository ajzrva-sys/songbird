# Candidate continuity

## Release build and GitHub source handoff — 2026-10-06

At the owner request, the current nested candidate was release-built and packaged
as `Songbird.app`, with deep strict signature verification. Quick tests passed
353 XCTest cases (two optional skips) and 398 Swift Testing cases. The app was
not installed or launched. GitHub handoff uses a temporary clone of
`https://github.com/ajzrva-sys/songbird`, preserving existing main history and
remote-owned control files absent from the local source export. The publication
manifest is resealed in that checkout. Manual hardware/UI gates remain pending.


## Artist Albums view — 2026-10-06

Artist pages now open with the existing album-card grid and an Albums/Tracks
switch. Tracks retains the previous searchable table. Artist membership matches
the table's exact track-artist names, including compilation appearances; album
actions keep complete multi-disc groups and distinct editions. Search, Favorites,
sort and View controls reuse the existing grid, with separate per-artist scroll
anchors. New artist pages start in Albums.

The 34 focused cases pass. Full quick after release compilation passes 353 XCTest
cases (two optional skips) and 398 Swift Testing cases. The first full run and a
focused rerun exposed an existing audio-poller cancellation race; both receipts
are retained rather than treated as a clean first run. The alternate disposable
app has release package parity. Isolated replay verifies Albums defaults for two
artists, compilation inclusion, Albums/Tracks switching and album/Back navigation.
Injected search text did not reach the shared search binding, so its empty/reset
UI path remains unverified; focused filtering checks pass. Pointer hover/focus
replay and mini artwork activation remain separate gates. The installed app and
normal library are untouched; receipts are in TESTING.md.

## Mini-player artwork returns to full player — 2026-10-06

Source now makes the small track artwork in Modern/Glass Mini Player a native
button labeled Show Full Player. It calls the existing return action, restoring
the explicit main-player scene and closing Mini Player without touching playback.
Artwork geometry remains 28 points; Classic/Strip retain their existing return
controls. Focused window/navigation checks and full quick pass; receipts are in
TESTING.md. No app was packaged, installed or launched. Actual pointer activation
and the resulting window transition remain for the next disposable UI pass.

## Album Play hover feedback — 2026-10-06

Source now makes the album Play button's highlight and brightest part of its
theme-accent rim follow the pointer. Continuous local hover also tilts the
surface toward it, bounded to four degrees on each axis; leaving restores center.
Hover enlargement, pressed compression, the 44-point circular target and native
playback action remain. Keyboard focus uses a centered highlight. Reduce Motion
keeps the highlight stationary and removes tilt, scaling and animation.
Focused checks and full quick pass; receipts are in TESTING.md. No app was
packaged, installed or launched. Pointer/animation replay remains pending for
the next disposable UI pass together with the outline/alignment changes below.

## Album grid focus outline and alignment — 2026-10-06

Source now uses the existing rounded album outline for card focus as well as
selection, with muted accent for focus. The system focus effect is suppressed
only while the card owns focus, preserving Play/Open button focus cues. Adaptive
columns top-align cards so optional metadata does not offset neighboring covers.
The focused checks and full quick suite pass; exact receipts are in TESTING.md.
No app was packaged, installed or launched. Rendered focus/alignment verification
remains pending for the next disposable UI pass.

## Installation and artwork mini-player action — 2026-10-06

At the owner's follow-on request, the UI improvements and small Now Playing
artwork button are installed in `/Applications/Songbird.app`. The artwork uses
the existing mini-player window action, preserving playback and disabling the
button during Layout Studio editing. Both main-player placements share it.

`build.sh` now reveals its finished `Songbird.app` in Finder by default. The
`--no-reveal` option suppresses Finder; `--open` additionally launches the app.
Normal app launch/restart remains with the owner. Both previous installations
are preserved as rollback apps in `/Applications`.

The updated release, full quick checks and all 44 installed package entries
verify. Disposable native button activation opened Mini Player with the same
paused track at 0:05. Physical pointer injection did not change the window and
remains unverified, consistent with the earlier runner limitation. Broader UI
acceptance gates recorded below remain open. Installation receipts and exact
rollback paths are in `/private/tmp/songbird-ui-20261006/mini-click-install-receipt.json`.

## Ten UI improvements — 2026-10-06

All four source stages of the [approved UI plan](docs/exec-plans/active/ui-improvements.md)
are implemented in the nested candidate at
`/Volumes/projects/songbird-public/songbird-public`. Search is persistently scoped
to the visible collection, active facet chips survive a hidden browser, and empty
states expose the appropriate existing action. Library View controls reuse saved
preferences; album cards expose Play/Open while retaining modifier selection and
double-click playback. The main player has clearer labels and a larger seek area
with its own height preference; mini-player sizing stays independent. Upcoming
queue controls use occurrence IDs and guard Clear/Undo against newer queue or
playback changes.

Health freshness is distinct from previous counts and timestamps. Metadata Save
Changes preserves untouched mixed Favorite/Rating values and captures its write
destination at submission. Catalog saves and partial file-write outcomes have
separate counts. Activity provides full current-session messages plus durable,
controlled summaries and filename-only failures: 500 terminal records, 30 days,
2 MiB, and 100 details per operation. Storage is atomic, interrupted work is
identified after restart, unreadable history is preserved until Clear History,
and flushing cannot delay quit beyond two seconds.

Current source verification passes 120 focused cases, the full 745-case Swift
quick run (two optional-store skips, no failures), 68 Thread Sanitizer cases, and
optimized compilation. The historical Finder-notice failure did not reproduce.
Python retains one missing-`Package.resolved` legal-input error in 116 cases with
two optional skips. Six missing plan-standard/optional-skill harness issues remain.
The no-Git disposable runner now records scoped current-source provenance in
schema-3 manifests without importing excluded material or weakening privacy and
package-parity checks. Exact receipts, commands and limitations are in TESTING.md.

Disposable window evidence verifies album Play/Open and playback-preserving
navigation, hidden-browser filter chips, current-entry-preserving queue Clear/Undo,
actionable empty states and an 800×600 empty-library layout. Health file checks expose
Not checked/Current, findings and freshness timestamps. A completed Activity
warning and three filename-only failure details persisted through an isolated
relaunch, with the panel initially collapsed. The repeated full quick in
`quick-health-fix.log` retains the same 351 XCTest/two skips and 394 Swift Testing
results with no failures.

Large repair run `20261006T204651Z-32035` passed release compilation in 79.53
seconds and package parity, with scoped schema-3 source hash
`c58426656f3da15f4332133f861ea7665b7c45664cc38e587380a2b9b60d8f25`.
Its UI showed 10,000 tracks/910:50:00 and 1,000 albums with persistent Search/View.
Native menu actions enabled compact Now Playing and switched Blue Monday/top to
Purple Rain/bottom. Paused compact Clear/Undo preserved Fixture Track 02001 and
restored the exact seven upcoming entries, eight tracks/41:20; the before/after
AX captures are byte-identical. The supported 956×520 minimum with both panes
was visually usable. An 800×600 AX bypass was below that documented minimum and
clipped the pane, so it is excluded from acceptance. Activity's Settings action
opened Appearance, but coordinate selection of Library did not change panes.

The rebuilt Health dashboard screenshot fixes the wrapped-timestamp overlap
with Consistency; the original failure remains recorded and the finding is
marked fixed by replay. Deep/shallow dashboard AX serialization and keyboard
injection remained unavailable. Temporary broker busy/no-exact-window gaps did
not establish a hang; status confirmed the app was running, with no latency
measurement claimed. Keyboard/modifier/double-click and seek-pointer flows,
compact Play Next/Remove routing, mixed-editor interaction, import Activity with
active warnings, long titles, the full theme/mini-player matrix, and dashboard
AX acceptance remain pending. Five completed fixture runs have schema-conforming
reports with verdict incomplete; the initial album label finding is also fixed.
All tested apps and brokers were stopped. The plan stays active for its pending
UI gates. This is source and disposable-profile delivery only. The installed
app and normal library were not changed; full UI/hardware acceptance remains
open. Earlier dated sections retain their original receipts and limitations.

## File tag recovery automation — 2026-10-05

Source now exposes **Read File Tags** in missing-metadata/artwork Health checks.
It reads four unique files per batch, fills missing catalog values/artwork from
embedded tags, preserves existing catalog choices and avoids BPM analysis.
The reader handles numeric iTunes genre/year keys, binary track/disc pairs,
ID3 identifiers and tagged titles previously masked by a filename fallback.
**Save Checked Tags to Files** writes deterministic checked missing-field
suggestions, preserves existing file values, verifies a temporary copy before
replacement and updates the catalog only for verified file values. Inferred
titles/numbers and consistency rewrites are excluded; file changes have no
catalog Undo. Scope, tests and limits are in the [completed source plan](docs/exec-plans/completed/file-tag-recovery.md)
and TESTING.md. No normal library or installed app was modified by this source
pass. Full quick retains the known Finder-notice failure; black-box UI remains
unverified because the disposable wrapper requires missing Git metadata.

Follow-on delivery: the normal release build and package completed and passed
strict deep signature verification on 2026-10-05. The updated app is installed at
`/Applications/Songbird.app`; the prior app is retained externally as
`Songbird-before-file-tags-20261005.app`. Restart is user-controlled. Build and
installation receipts are in `/private/tmp/songbird-tag-repair-20261005/`.
This delivery does not change the isolated UI or hardware validation limits.

Follow-on source exposes **Save Library Artwork to Files…** in Missing Artwork
Health, including when that catalog check has no findings. It resolves all saved
album covers from a fresh context, shares one cover read across an album's tracks,
deduplicates paths and fills only files without embedded pictures. Existing
pictures, including undecodable AV tags and empty FLAC picture blocks, remain.
Temporary copies must retain recognized tags/sample rate/duration and the exact
saved JPEG/PNG bytes before replacement; current catalog cover/path/album and
uncached original file properties are rechecked. Cancellation applies before
commit. The existing AV writer cannot export MP3; those files are retained with
a clear per-file failure. This source extension has not been packaged by the
source pass. Follow-on validation and receipts are recorded in TESTING.md.
Durable AV metadata-bag load errors retain originals. Compact YYYYMMDD release
dates now expose their four-digit year without rewriting the physical date.

Final delivery: the artwork/date extension was built with the official offline
release command and installed at `/Applications/Songbird.app`. Strict deep
signature verification passed; all 44 file/symlink entries match the package.
Executable SHA-256 is `5db11556ead0cb58f68ca8bba4f3dedd565f844739a75cf2482c42e3c6c03119`.
The original rollback remains intact; the app was not quit or relaunched.
Receipts remain private under the dated album-art-repair workspace. Normal-profile
UI and hardware acceptance remain unverified.

## Current implementation — 2026-09-15

This is the separate publication repository, prepared without importing development
history. The owner authorized its initial commit and public GitHub push on 2026-09-15
to https://github.com/ajzrva-sys/songbird, using the verified current source payload.
The original development checkout has not been modified; the normal library has
not been used for this work.

The owner authorized [the ready-to-share plan](docs/exec-plans/active/ready-to-share.md).
The previously prepared Discogs review and maintenance slices were already present;
the 18 CD foundation paths were integrated after matching all before/final hashes.
The remaining CD presentation, thumbnail expiry, conservative system metadata and
long-rip recovery changes are now integrated. Completed audio survives metadata
expiry; refresh or original CD metadata can resume the import.

The exact reviewed aubio/FLAC/ogg outputs are adopted. Previous library bytes and
installer receipts are preserved externally. GRDB source remains vendored for
`SONGBIRD_OFFLINE_DEPS=1`. The release checker now validates every component record,
including actual source membership, hashes and build/evidence files.

About is compact and opens the bundled, offline legal document window. Canonical
notice/source documents are synchronized. The 29 inherited private file modes were
normalized to the ordinary 0644/0755 source-package contract, preserving before modes
in preparation evidence. The ad-hoc package and recorded technical checks pass. Exact sealed archive hashes
and post-seal offline rebuild results are in the companion RELEASE-RECEIPT.json.

## Decisions and boundaries

Keep Songbird, Discogs importing and permanent saved covers, tags, filenames,
reports and Undo. Temporary provider responses may expire. System Now Playing uses
original CD-Text/default metadata with no transient Discogs image. Naming is approved;
privacy/contact review is waived. The five owner decisions, including restored bird artwork, remain nonblocking,
not claims that a provider granted permission or that a review was performed.

The implementation run and before-images are retained under
`/private/tmp/songbird-ready-j_3o0gnc`; final artifacts belong in the sibling
`songbird-public-verification` directory. Do not include build trees, Git history,
private media or normal-library files in the source payload.

## Original integration validation

Passed: 105 Python checks (2 opt-in rebuild skips), 284 XCTest cases (2 optional
store skips), 334 Swift Testing cases, one added disk-persistence case, optimized
compilation and 25 audio TSan cases. Packaged notices load offline; synthetic
playback/pause, canned Discogs import/expiry and saved-cover offline restart were
observed. See publication/ready-build-proof.json and the companion release receipt
for exact evidence and post-seal source-archive rebuild results.
The owner confirmed physical-CD playback, ripping and eject work. AirPlay and
Intel/universal support remain untested. This pass produces
an ad-hoc signed Apple Silicon hobby build. Its earlier local-only boundary was
superseded by the owner's GitHub publication request; Developer ID signing and
notarization remain outside the work.

## Historical records

`docs/PUBLICATION_BASELINE.md` and the completed baseline plan describe preparation,
not the current payload. The earlier release-licensing-remediation plan retains
dated research/build receipts. Its paused status and pending S7 request are superseded
by the owner's explicit implementation authorization. The final manifest will describe
the exact current payload while `publication/changes.json` preserves preparation origins.

## Bird artwork restoration — 2026-09-15

The owner explicitly approved restoring the original bird after the specific
artwork research. All 26 existing PNG resources are copied byte-for-byte from the
preserved development checkout; the project-authored CD symbol stays. The image
inventory and notices describe retained artwork, not new authorship or cleared
trademark rights. The prior record-style archives remain preserved externally.
The original per-icon Dock crops and Amber Bird label are restored. Current checks
passed: 105 Python cases (2 optional skips), 285 XCTest cases (2 optional skips),
334 Swift Testing cases and optimized compilation. The bounded disposable UI report
and final package/offline-rebuild receipts accompany the bird handoff at
`/Users/aji/project/songbird-public-verification/ready-to-share-0.1.0-bird`.
Audio/data behavior is unchanged.

## Owner-selected missing artwork — 2026-09-15

The owner supplied songbirdimage.png and chose it as the missing-artwork placeholder.
Its original 1254×1254 bytes replace only missing-album-artwork.png; the Dock icons,
player bird, existing album covers and runtime code are unchanged. The asset record
and bundled notice identify this user-provided illustration separately. Current
package checks are in the ready-to-share-0.1.0-cute-bird companion receipt.

## Pane divider spacing — 2026-10-05

Source now reserves one point for each grey pane divider, removing the dark
background gutters beside it. The invisible eight-point resize target remains.
Tests and limitations are recorded in TESTING.md. Built and reinstalled in
`/Applications/Songbird.app` at the owner's request on 2026-10-05; all 44 package
entries and the unchanged signing identity verify. The previous app is retained
in `/Volumes/projects/songbird-public-verification/divider-20261005/`. Normal app
restart is left to the owner. Black-box visual verification remains blocked by
the absent Git metadata required by the disposable UI runner in this copy.

## Missing artwork sorting and progress — 2026-10-05

Installed Missing Album Art sorting (uncovered albums first) and an artwork-rescan
counter scoped to missing album groups, with shared folders checked once per run.
The rescan previously selected the correct groups but displayed the full track
count. Focused tests and release packaging pass; full quick retains the unchanged
Finder-notice failure. Black-box visual coverage remains open. Details and source
hashes are recorded in TESTING.md and the bounded plan.
