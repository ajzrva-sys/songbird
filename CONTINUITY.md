# Candidate continuity

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
