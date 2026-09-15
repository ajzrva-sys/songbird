# License scope

## Owner-confirmed original portions

Copyright (C) 2026 Andrew Zimmerman.

On 2026-09-15 the owner confirmed this exact copyright wording and authority to
license the project-owned original code and newly authored replacement artwork
under GPL-3.0-or-later, with third-party material retaining its own terms. This
records the owner's confirmation, not an invented assignment, employer permission,
trademark clearance or independent legal opinion.

The grant in [NOTICE.txt](../NOTICE.txt) applies to project-owned original portions
of Sources/, Tools/, scripts/, tests and project documentation, and to project-authored
assets and generator/catalog source. It does not relicense the restored historical
bird images. The full
license is [LICENSE](../LICENSE). Existing per-file third-party notices take precedence
for their material. The combined application retains its GPL-linked aubio dependency;
this is not a permissive license for the combined application.

## Retained third-party and fixture boundaries

| Material | Terms and scope | Status |
| --- | --- | --- |
| Vendor/aubio/src and imported aubio library code | Source headers: GPL-3.0-or-later; Ooura author-site permissive grant and per-file notices retained | Source identity and nested notices reviewed; reviewed outputs adopted and hash-verified |
| Vendor/FLAC runtime libraries and FLAC-derived bridge headers | Applicable Xiph/Josh Coalson BSD notices remain intact | Original supplier chain unrecovered; exact approved replacement source notices delivered; controlled builds tested and reviewed outputs adopted |
| Vendor/FLAC/source full upstream packages | BSD codec scope plus source-only GPL/LGPL/FDL and per-file notices | All regular source members supplied without content patches; original archive modes recorded, delivered modes made safe; no blanket relicensing |
| GRDB.swift 6.29.3, revision 2cf6c756e1e5ef6901ebae16576a7e4e4b834622 | Root MIT, Rails-derived MIT, and Swift-derived Apache-2.0 with Runtime Library Exception; full notices/texts delivered | Exact production source supplied with approved test-target-only manifest adaptation; parent offline and network-denied builds passed; final source-archive acceptance recorded in the companion release receipt |
| Synthetic Tests/Fixtures media | Existing CC0-1.0 declaration in [fixture manifest](../Tests/Fixtures/manifest.json) | Unchanged; not relicensed by the application notice |
| Current runtime images and retired screenshots | Project-authored CD symbol: GPL-3.0-or-later. Historical bird artwork retains its applicable terms; no blanket relicensing | Owner approved restoring the 26 PNG assets after the artwork research, then supplied songbirdimage.png as the missing-artwork replacement. Current hashes and the recorded selections are in [artwork decision](../publication/artwork-decision.json). Four old screenshots remain excluded. |
| Discogs/MusicBrainz/Last.fm content and user media | Their own applicable rights and service terms | Not relicensed as application code; no user-content migration authorized |

See [THIRD_PARTY_NOTICES.txt](../THIRD_PARTY_NOTICES.txt) and
[SOURCE_CODE.md](../SOURCE_CODE.md). Third-party source is not blanket-relicensed.
Do not manufacture missing attribution, remove copyright notices, or infer source
provenance from binary ABI labels. The current name, bundle IDs, persisted theme
identities and preference/storage keys remain compatibility identifiers, not proof
of trademark permission. The owner approved retaining the Songbird name for
release; [that decision](../publication/brand-decision.json) is owner-nonblocking
and does not claim independent trademark clearance.

## Distribution status

The local hobby build passed source correspondence, notice delivery and transient
system-display checks. Exact app/source archives, validation scope and offline
rebuild evidence are recorded in the companion release receipt. Original-code
authority remains recorded. The owner approved retaining the historical bird
artwork on 2026-09-15 after reviewing the licensing/trademark research; artwork
and branding are owner-nonblocking, not independently verified rights clearance.
The exact runtime image inventory remains hash-checked. Discogs retention and the
waived privacy/contact review retain their existing owner decisions in
[release gates](../publication/release-gates.json). No public upload or initial
commit is part of this pass.
