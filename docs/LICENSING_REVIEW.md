# Pre-publication Licensing Review

Candidate context: this audit describes the original development checkout and its historical HEAD, not this new repository's ancestry. The reference/application trees described in LIC-001 are intentionally absent here. See [the baseline record](PUBLICATION_BASELINE.md) for the separately verified export boundary.

Historical remediation checkpoint (superseded by the ready-to-share build and
owner-approved bird restoration; see CONTINUITY.md and publication/artwork-decision.json), 2026-09-15: the owner selected GPL-3.0-or-later and confirmed
original-code/new-art copyright authority; [license scope](LICENSE_SCOPE.md) records
that decision. Canonical texts, unsigned staging and the packaged-first legal loader
are tested; About legal-sheet code compiles. This supersedes LIC-002's missing-root-license
observation and repairs LIC-003's known text-delivery recipe gaps, not its complete
source-correspondence or rendered UI gates. A fresh signed package was not produced.
All 27 runtime images are now original geometric outputs with tested provenance;
four old screenshots are removed. Recovered Ooura/Mario Lang and GRDB's nested
Rails/Swift notices are delivered and tested; see [vendor source review](vendor-source-review.md).
Brand clearance, source-to-output correspondence, final notice/UI delivery, Discogs
policy and privacy remain unresolved. No binary adoption or public release occurred.
The dated findings below remain historical evidence; current work is PUB-REMEDIATION
in [NEXT_STEPS.md](../NEXT_STEPS.md), not the original checkout's PUB-001 task.

Reviewed: 2026-09-15. Scope: the current Songbird working tree, selected existing build output, and Git history intended for possible GitHub publication. Signing, notarization, deployment, and hardware acceptance are excluded.

Verdict: **not cleared for publication as-is**. This is an engineering compliance review, not a legal opinion or a determination of infringement. No project license was selected, rights-holder permission obtained, release built, or history rewritten by this review. Decisions remain under `PUB-001` in `NEXT_STEPS.md`.

## Findings

### LIC-001 — Blocker: existing main history distributes unrelated applications

The inspected HEAD is `4630e93f4f80e266100af166229ecd7f37082776`, with 26 reachable commits and 12,613 tracked paths. The index matches HEAD; the large deletions are unstaged. HEAD includes:

| Tree | Tracked paths at HEAD |
|---|---:|
| `Swinsian.app/` | 397 |
| `Cog-main/` | 4,688 |
| `museeks-0.23.4/` | 293 |
| `Nightingale.app/` | 587 |
| `Nightingale/` | 502 |
| `nightingale-media-player-nightingale-hacking-9b9c8bf/` | 6,094 |

`HEAD:Swinsian.app/Contents/Info.plist` identifies Swinsian 3.0.8, build 638, with `com.swinsian.Swinsian` and its own copyright. `HEAD:Swinsian.app/Contents/MacOS/Swinsian` is a 7,702,160-byte executable, Git blob `b3ee6a11d6ed39cab6147870682db27c8c67474c`. No permission to redistribute the Swinsian application was established. Third-party component credits are not a grant for the application itself.

The reference collections are not uniformly licensed. For example, historical `Cog-main/Frameworks/snes9x/snes9x/LICENSE:169–182` limits its grant to noncommercial use; `Cog-main/Frameworks/Shorten/Files/shorten/doc/LICENSE.shorten:8–14` restricts incorporation into sold products; and `Cog-main/Frameworks/File_Extractor/File_Extractor/unrar/license.txt:13–21` has use and notice conditions. The reference review also found binary library archives and recording/soundfont fixtures whose complete redistribution compliance was not established. These are reference-distribution concerns, not evidence that current Songbird links those components.

A normal push of main includes its reachable history. Committing deletions next does not remove the earlier copies. A naive copy of the current working folder is also unsafe: the reference source directory currently contains untracked nested `Nightingale.app/` and `Nightingale/` distributions with 587 and 502 files respectively. Necessary current product inputs, including `Vendor/`, build scripts, and much of `Sources/`, are also untracked.

Remedy: choose an explicitly allowlisted new public baseline without unrelated reference applications/media, or separately authorize and audit history filtering across every ref to be published. Preserve this local checkout. Do not use bulk staging, a folder-wide copy, or a mirror push as the publication procedure. Local `refs/codex/turn-diffs/checkpoints/` also exist; ordinary main pushes do not send those refs, but mirror/custom refspecs can.

### LIC-002 — High: aubio determines combined-application licensing

There is no root project license; `README.md:98–103` correctly records the unresolved choice. The current dependency is substantive, not an unused development tool:

- `Package.swift:58–67` links `Vendor/aubio/libaubio.5.dylib`.
- `Package.swift:80–89` makes `AubioBridge` a dependency of `SongbirdLib`.
- `Sources/Library/MetadataReader.swift:306–364` passes decoded audio to the bridge for BPM estimation.
- `Sources/AubioBridge/SBAubioBPM.c:12–29` invokes aubio tempo/vector APIs.
- `otool -L .build/release/Songbird` confirms a real `@rpath/libaubio.5.dylib` dependency in the existing release executable.
- `Sources/AubioBridge/include/aubio/tempo/tempo.h:2–17` retains the upstream GPL version 3-or-later notice. The shorter `Vendor/aubio/NOTICE.txt:4` calls it GPLv3.

The FSF's stated interpretation is that both static and dynamic linking produce a combined work covered by the GPL; GPLv3 section 5(c) requires the covered work as a whole to be licensed under the GPL.[1][2] Plan distribution of the linked application on that basis unless qualified review or a separate rights-holder license establishes a different route. A `.dylib` or C wrapper does not provide a licensing escape.

Owner choices:

1. Keep aubio and distribute the combined application under GPLv3-compatible terms, satisfying its notices and corresponding-source requirements. Original portions may carry compatible permissive terms, but a blanket MIT/BSD description of the entire combined distribution would be misleading.
2. Replace/remove aubio, its copied headers and distributed binary/source as appropriate, using independently authored BPM analysis or another verified dependency, then choose the license for the remaining original work. Do not translate aubio implementation code and call it independent.
3. Obtain a separate applicable license from the relevant rights holder(s); no such permission was found in the reviewed files.

This decision does not resolve historical redistribution or artwork/trademark rights. Keeping unrelated reference trees in the same repository also does not, by itself, establish that their copyleft applies to independently implemented Songbird code: aggregate distribution and a linked combined program are different questions.[1]

### LIC-003 — High: distributable notices and source-delivery contract are incomplete

**Full GPL omitted from app packaging.** `scripts/package-songbird.sh:104–108` copies the aubio binary and seven-line notice, but not `Vendor/aubio/src/COPYING`. The notice only links to the GNU licenses site and generic aubio repository. `Sources/Resources/` has no license/notice resources that would compensate through the later copy loop. GPLv3 sections 4 and 6 require a copy of the license and corresponding-source compliance; a generic license URL is not the license copy.[1]

**GRDB notice omitted despite actual linked code.** `Package.resolved:4–9` pins GRDB.swift 6.29.3 at `2cf6c756e1e5ef6901ebae16576a7e4e4b834622`; the local checkout matches and is unmodified. Its `LICENSE:1–7` grants MIT terms and requires retention of its copyright and permission notice. `Package.swift:83` includes the product. `nm -g .build/release/Songbird` returned 5,008 lines containing GRDB symbols, despite no direct `import GRDB` in the scanned product Swift files. Packaging includes no GRDB notice, and `README.md:102` only says its upstream license applies. Either ship the full applicable MIT notice or remove the dependency through separately validated product work.

**Source exists, but release correspondence is not established.** `Vendor/aubio/src/COPYING`, its source subtree, `scripts/rebuild-aubio.sh:22–29`, and `scripts/aubio-cmake/` are already present. Do not describe aubio source as wholly missing. However, no release-specific, clean-checkout source-delivery validation was performed. `Vendor/aubio/src/VERSION:1–7` identifies 0.5.0-alpha, while the custom CMake file sets a dylib version of 5.4.8; these are different kinds of version numbers, not sufficient upstream revision provenance.

For a release, record the exact upstream revision/source snapshot, local changes, configuration, and build instructions. Provide the complete corresponding source for the released combination, including required non-system dependency sources or equivalent maintained access. The GPL's definition includes build/install scripts and specifically required shared libraries; a bare generic upstream link does not establish correspondence or availability.[1] Do not confuse correspondence with mandatory bit-identical compiler output.

`Sources/Views/AboutSongbirdView.swift:16–36` currently provides no copyright/license/warranty information or license access. If retaining the GPL distribution route, implement an accessible legal-notices surface and assess GPLv3 sections 0/5(d), including their exception, rather than assuming an About panel with only product/version text is sufficient.[1]

Positive: `Vendor/FLAC/NOTICE.txt:3–29` contains BSD-style libFLAC/libogg copyright, redistribution conditions and disclaimer, and the packaging script copies it at line 106. The inspected dylibs depend on each other/system libraries, not hidden FFmpeg or other non-system dylibs. Exact original binary provenance is still not independently certified.

Remedy: one explicit license/notice inventory, full distributable license texts, release-specific source instructions, and a packaging assertion that all required notices are delivered. An owner-selected root license alone is insufficient.

### LIC-004 — High: proven legacy artwork copying and unresolved current branding

The reference tree's `TRADEMARK.txt:1–5` explicitly identifies the Songbird name, logos, and icons as Pioneers of the Inevitable trademarks and states that it does not express or imply permission to use or distribute them. `debian/copyright:38–41` similarly mentions names/logos/skins. Current product branding uses Songbird throughout `README.md:1–5`, `Sources/Views/AboutSongbirdView.swift:18–30`, and packaging metadata.

This is concrete evidence that the source license must not be treated as trademark permission. It is not verification of present ownership, registration, enforceability, abandonment, or infringement. A source-only native rewrite and an "inspired by" statement do not themselves establish clearance.

Asset findings:

- Current legacy `Resources/songbird-logo.png` is byte-identical to the reference's `app/skin/branding/about.png`: SHA-256 `bcf5041f86decc7e4de45c0258a72f3b727fb27a76dd11988d03383e15709105`.
- Historical commits record use of the reference's Last.fm-extension logo. That extension's `LICENSE:1–25` contains a BSD-style grant with copyright/notice retention and non-endorsement conditions. Verify asset coverage rather than assuming the reference's root GPL covers every image identically.
- The current preferred `Sources/Resources/songbird-logo.png` is **different** from its HEAD version. Current SHA-256 is `c4e5ed46b28578790a732af899725526592be9224e837e259fe1d5cda017c2d8`; HEAD is `cbe456e703398c42bbfc7171bd318140d2c9e3294fc829c267abaea6ac16a525`. Do not claim that the current mark was proved to be the exact old Last.fm asset. Its creation/rights chain remains unresolved.
- All 21 themed `Sources/Resources/dock-icon-*.png` assets are untracked. The inspected renderer crops/scales/clips supplied images; no original-creation/permission record for the set was found.
- `Sources/Resources/missing-album-artwork.png` is identical to root `image.png`, SHA-256 `1c20795d863bf05537e46112147a1cff65f0c8389296b9599a8b9ed9e59a64c6`. That match establishes local duplication, not authorship or rights.
- `scripts/package-songbird.sh:119–140` selects an icon and copies every file in `Sources/Resources/`. Hiding a choice in the UI would not stop its distribution.
- The fresh README screenshots have fixture/capture provenance, but display existing product assets; their own notes explicitly leave those rights unresolved. Reference screenshots under `songbird-images/` also lack a verified per-image redistribution record.
- No copied official Compact Disc wordmark was established for `Sources/Resources/audio-cd-mark.svg`; the inspected SVG/native code use generic disc geometry. Record provenance, but do not call this a proved CD-trademark violation.

Remedy: obtain/document appropriate rights or replace unresolved artwork with independently created assets, and separately resolve the product name/branding. Create a per-asset manifest with author/source, precise applicable license or permission, modifications, and required notices. Exclude unnecessary legacy copies from the approved baseline and recapture affected screenshots after replacement. Recoloring or renaming a derived asset does not establish independent authorship.

### LIC-005 — High for enabling the service: Discogs attribution and freshness gaps

The retrieved Discogs API terms require the notice "Data provided by Discogs." directly next to API data, hyperlinked to the Discogs page containing it. They also say not to display content more than six hours older than the information on Discogs, and not to cache/store it longer than necessary for the service.[3]

Current source does not implement a corresponding policy:

- `Sources/Discogs/DiscogsSearchView.swift:175–230` presents artwork/title/artist/year without that notice or linked source. The scanned bulk-artwork and genre result surfaces likewise contain no required notice.
- `Sources/Discogs/DiscogsArtworkSearchCache.swift:5,24–36` permits cached results for 30 days, with no revalidation at retrieval.
- `Sources/Discogs/DiscogsBulkReviewView.swift:415–418` displays cached candidates directly; the genre workflow does the same.
- `Sources/OpticalDisc/DiscogsCDMetadata.swift:8–26` uses `AudioCDMetadataCache` and returns its cached results immediately; its default lifetime is also 30 days (`MusicBrainzCDMetadata.swift:244–256`).

A 30-day TTL does not prove a given record changed at Discogs, but it cannot enforce the retrieved freshness requirement. Reducing a TTL alone also does not settle permanent artwork/metadata imports: source/provenance is not preserved as a separate rights policy in the historical design. Review the applicability of API-contract restrictions versus the underlying CC0 metadata grant with appropriate expertise, especially for user-owned saved tags/covers. Do not delete existing user artwork or metadata as an audit "fix."

The API terms distinguish CC0 catalog fields from restricted data including user images. Downloading a cover does not establish an unrestricted copyright license to redistribute it as part of the repository, fixtures, or marketing.[3] The old claim at `docs/discogs-album-art-plan.md:5` that there were "no attribution, no licensing hurdles" was contradicted by the current terms and has been corrected by this review.

Remedy: required linked attribution across result/display paths; a provider-specific revalidation/cache policy; and an explicit design/permission decision for persistent imported artwork. This is an operational API/content compliance issue, not evidence that simply publishing independently authored client source is forbidden.

## Lower-risk items and explicit limits

- Primary audio fixtures declare CC0-1.0 and synthetic generation (`Tests/Fixtures/manifest.json:3–5`). The independent reference review inspected mathematical generation code. Do not extend that declaration to third-party media in the reference trees.
- The MusicBrainz CD query requests `recordings+artist-credits` (`Sources/OpticalDisc/MusicBrainzCDMetadata.swift:137–142`); no supplementary tags/ratings request was identified. MusicBrainz distinguishes CC0 core data from supplementary CC BY-NC-SA data.[5] Calling its API does not mean its server's GPL license becomes Songbird's application license.
- Last.fm publishes separate API/data terms, including credit/link requirements and commercial-use conditions.[4] No commercial authorization or complete scrobbling/data-display compliance audit was performed. Do not conflate those service terms with the old Last.fm extension's code/asset license.
- The bounded source-provenance comparison found FLAC public headers shared with the reference collection, with notices retained. Shared upstream bytes do not establish that the source was copied from Cog. No comprehensive fuzzy/translated-copy review or clean-room certification was performed.
- No secrets, real-library databases, private media, or remote-publication state were inspected. This is not a secrets/privacy clearance, a trademark search, or a review of unreachable/reflog-only Git objects.

## Recommended publication sequence

1. Owner chooses the aubio/GPL route and the current asset/branding rights route. Do not silently select a project license.
2. Owner approves an explicit current-file publication allowlist and a new-baseline versus retained-history strategy. Keep unrelated local work intact.
3. Add precise license scope, full third-party notices, asset provenance, and release-specific corresponding-source instructions. Resolve or explicitly withhold affected online integrations pending their policy work.
4. Validate the selected export in a clean disposable checkout: focused/full tests and release compilation, dependency rebuild/source completeness, and packaged notice/resource assertions. Signing is outside this review.
5. Inspect the exact refs/files to be pushed and release attachments, including historical objects if retained. Publication and any history changes require separate approval.

## Verification performed

- Read current package manifest, lockfile, vendor notices/source configuration, packaging, About, BPM, metadata/cache and attribution paths.
- Inspected actual dylib load commands with `otool -L`; inspected the existing release executable with `nm -g` for GRDB inclusion. The executable was not rebuilt, so this is existing-artifact evidence corroborating the current manifest, not a new release validation.
- Inspected Git branch/status, HEAD/index path inventories, selected historical licenses/application metadata, and reference asset SHA-256 matches. Independent read-only reviews additionally inspected commit/checkpoint inventories, archive members, screenshot provenance, and bounded source matches.
- Retrieved GNU GPL/FAQ and official service terms; citations below include evidence-backed sources accessed on the review date.
- Documentation validation passed: `./scripts/validate-agent-harness.sh docs/LICENSING_REVIEW.md docs/discogs-album-art-plan.md` checked required harness files/directories and local links; the grounded-citation validator passed `--strict --evidence`. Citation coverage statistics count web references, not the numerous local path/ref evidence citations in this report.
- No product source, dependency binary, resource, user data, or Git index/history was changed. Documentation-only edits record this review and correct the contradictory Discogs assumption. No build, tests, app launch, packaging, signing or network publication was performed; none is claimed as passing.

## Sources

[1] https://www.gnu.org/licenses/gpl-3.0.html — GNU GPL version 3
[2] https://www.gnu.org/licenses/gpl-faq.en.html — FSF GNU licenses FAQ
[3] https://support.discogs.com/hc/en-us/articles/360009334593-API-Terms-of-Use — API Terms of Use – Discogs
[4] https://www.last.fm/api/tos — API Terms of Service | Last.fm
[5] https://musicbrainz.org/doc/About/Data_License — About / Data License - MusicBrainz
