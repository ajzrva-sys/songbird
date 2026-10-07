# Recover file tags and save safe Health repairs

## Purpose and scope

Library Health can show stale missing values after another tag editor repairs the
audio. Expose one bulk action to recover missing catalog fields and artwork from
the existing files without tempo analysis. Read MP4 binary number pairs and ID3
field identifiers correctly. Separately expose saving checked, deterministic
missing-field suggestions to files through the existing tag writer; preserve
existing file values, verify a temporary copy, and replace only after readback.
No provider lookup, filename guesses, normal-library access, playback changes,
app packaging/install/launch, schema/vendor changes, staging, or publication.

## Progress

- [x] Read current reader, writer, importer, Health/action boundaries and docs.
- [x] Confirm catalog-only Health Apply and missing binary number-pair decoding.
- [x] Preserve scoped source before-images and hashes.
- [x] Implement bounded recovery, safe durable writing and clear Health actions.
- [x] Run focused synthetic behavior tests and `./check.sh quick`.
- [x] Record current results, limits and source hashes in control documents.

## Decisions and discoveries

`.agent/PLANS.md` and Git metadata are absent in this copy. Follow the existing
self-contained plan format; before-images and run logs are under
`/private/tmp/songbird-file-tags-20261005`. Do not initialize Git or access the
normal store to compensate. Bulk recovery fills missing values; existing catalog
values are retained. File writes skip existing divergent values and restrict
selection to automatic-safe missing metadata proposals, never filename inference.
Read batches contain at most four unique paths; no catalog model crosses into
concurrent disk tasks. A fresh context resolves catalog values after reading.
The AV reader decodes numeric FourCC keys, raw format-specific metadata and
binary track/disc pairs. Its album-artist fallback follows a newly filled artist;
this does not create a physical album-artist tag. Safe file repair excludes titles.
The temporary-copy verification checks the edited value, other recognized tags,
artwork and stream properties. It is not an encoded audio payload checksum or a
claim that arbitrary unknown tags are independently verified.

## Validation and acceptance

Use generated fixtures and disposable SwiftData stores only. Test binary MP4 and
ID3 tag parsing, no-BPM fill-only recovery, verified permanent FLAC/M4A writes,
preserved existing tags/artwork/number totals, no write for conflicts, and no
replacement on failed readback. Run focused tests followed by the full quick
suite with isolated HOME/CFFIXED_USER_HOME/SONGBIRD_UI_TEST_ROOT and local GRDB.
No backend/audio edit: audio TSan and hardware gates are outside this scope.
Black-box UI remains a separate gate because the existing privacy wrapper
requires absent Git metadata. Completion is source implementation and tests;
the installed app and user's catalog are not changed by this plan.

## Initial results

Implemented in source on 2026-10-05. Focused validation passed nine XCTest and
36 Swift Testing cases. Final full quick ran 342 XCTest cases with two optional
store skips and the same two failed assertions in the unchanged Finder-notice
test; all 356 Swift Testing cases passed. The suite remains not green.
Exact commands, sandbox limitations and source receipts are in TESTING.md.
The scoped diff and source hashes are in the external run directory. The
LibraryHealth.swift before-image was reconstructed by reversing the two added
properties; other existing changed source files were copied before editing.
The documentation harness retains six existing missing plan/usability-skill
file/directory/link failures. No backend, normal-library, installed-app or
black-box UI verification was performed by this source implementation pass.

## Follow-on artwork embedding — 2026-10-05

Add **Save Library Artwork to Files…** to the Missing Artwork Health header,
including when the catalog has no missing covers. Resolve all current album-linked
tracks from a fresh context, reading each saved cover once per album. Fill only
absent embedded artwork through the shared action handler and existing writer.
Deduplicate paths, preserve existing pictures, verify neighboring copies against
unchanged recognized tags/stream properties and exact saved cover bytes, and
recheck current file and catalog cover/path before replacement. Progress and
cancellation apply to the unique paths. No catalog or normal-library mutations
are part of this source pass; root owns subsequent delivery.

- [x] Implement the bounded artwork service/action/UI extension.
- [x] Test actual FLAC/M4A covers, preservation, failures, stale/concurrent guards,
  deduplication and cancellation with generated fixtures/disposable stores.
- [x] Probe the existing AVFoundation MP3 export support without adding a new writer.
- [x] Run focused coverage and isolated quick; record source receipts and limits.

Durable AV reads and metadata-copy writing require successful metadata-bag loads;
normal catalog readers keep tolerant defaults. The final original-file guard uses
uncached URL properties in both artwork and metadata repairs. Recognized artwork
presence is preserved even when image decoding fails. The existing AV MP3 export
is unsupported on the generated fixture; it reports failure without replacing
the original. Compact numeric/text YYYYMMDD dates are read as their four-digit
year while the full physical date remains unchanged during other repairs.

Final follow-on focused validation passed two XCTest and 25 Swift Testing tests.
Final quick executed 342 XCTest cases with two optional-store skips and only the
same two unchanged Finder-notice assertions failing; all 365 Swift Testing tests
passed in 47 suites. The suite remains not green. Source hashes, before-images,
scoped diff and logs are in `/private/tmp/songbird-file-artwork-20261005/`;
TESTING.md records exact commands, isolated homes/profiles and earlier sandbox
failures. The documentation harness retains the same six missing-plan/skill
issues. No normal catalog/media, packaged app or black-box UI was used by this
source pass. Other formats, encoded-audio payload equality and opaque-tag
verification remain outside its acceptance claim.

Root delivery completed after source validation: the official offline release
build was installed at `/Applications/Songbird.app`; strict deep signing passed
and all 44 bundle entries match. The original app rollback remains intact. The
app was not quit or relaunched. TESTING.md records the final executable hash and
exact command; private build/install receipts remain outside the publication
payload. No normal-profile UI or hardware acceptance was added by delivery.
