# Discogs content policy and release decisions

Status: permanent saved artwork and imported metadata/report retention are
nonblocking by owner decision. Transient CD handling and system-display
implementation/acceptance remain open.
This is an engineering implementation/decision record, not legal clearance or a
license to third-party content. No existing user artwork, tags, Undo receipts or
library history is deleted or rewritten by this policy.

## Owner requirement: permanent saved album artwork

On 2026-09-15 the owner clarified that search results may be temporary, but selected
album artwork must be permanent. Once saved, a cover must remain available offline
across app/Mac restarts and search-cache expiry, until the user replaces or removes
it. Refreshing search results must not replace or remove a saved cover. This is a
product requirement; permission for the chosen acquisition source remains separate.

The owner subsequently selected **keep Discogs image importing**. Discogs remains
the source for this workflow: search, select a cover, download and save its bytes
permanently in the local library. Provider switching is not the selected remedy.
Research is now limited to establishing the applicable terms or permission for
this Discogs workflow; temporary results may still expire.

The owner then decided that the unresolved permanent-cover interpretation should
not block release. That decision is recorded as `owner-nonblocking` in
[release gates](../publication/release-gates.json), with a hashed
[owner decision record](../publication/discogs-artwork-decision.json).
Provider permission remains unconfirmed. Further clarification is optional follow-up,
not a prerequisite for releasing the saved-artwork feature. This supersedes earlier
instructions requiring provider confirmation as the artwork release gate.

The existing candidate already saves imported artwork separately from transient
search evidence. Preserve that behavior. Do not extend the five-hour response
policy to saved album artwork, saved thumbnails or Undo. No schema change or
existing-library migration is authorized by this clarification. The previous
G-DISPLAY decision concerns unsaved, transient CD artwork, not saved album covers.

### Research outcome and selected acquisition route

Primary documentation rechecked on 2026-09-15:

- [Mp3tag's import documentation](https://docs.mp3tag.de/tag-sources/import/)
  explicitly supports Discogs cover lookup, user-selected import and saving the
  image to a file. This establishes an existing product workflow. It does not
  disclose a permission agreement or establish Songbird's permission.
- [Discogs API terms](https://support.discogs.com/hc/en-us/articles/360009334593-API-Terms-of-Use)
  separately restrict storage duration, stale display and attribution. They do not
  expressly require deleting every image six hours after download. No explicit
  exception for permanent personal-library cover imports was established by this
  review. Retention necessary for a personal library is an interpretation to verify,
  not a permission already obtained.
- [Cover Art Archive](https://musicbrainz.org/doc/Cover_Art_Archive) is an independent
  acquisition option indexed by MusicBrainz release ID. Its published policy allows
  public access while explicitly leaving image-rights responsibility with the user;
  it is not a blanket copyright grant. Its linked Internet Archive terms could not
  be retrieved as text in this review, so this route is not marked legally cleared.
  This was an alternative considered during research; the owner selected retaining
  Discogs image importing instead.

Selected technical design: keep expiring Discogs search/preview records separate
from permanent saved artwork. Preserve the existing Discogs image download and
local artwork storage path. Validate temporary evidence before import; once the
image is saved, search-cache cleanup and freshness checks do not control its
retention or rendering. The user selects the exact cover; no provider or edition
substitution is part of this decision. Existing local/embedded artwork inputs remain.

For Discogs-sourced images, retain the unresolved interpretation in the record;
do not relabel the owner's decision as confirmed provider permission. Moving Discogs bytes to a
different path, embedding them in tags or relabeling their origin does not establish
permission. Preserve Discogs importing and permanent saved covers while the
provider question remains unresolved. Saved artwork is nonblocking by owner decision.

### Draft provider question — not sent

Songbird is a local desktop music player. We want a user to search Discogs, select
an album cover, and explicitly save that image as artwork for their personal music
library. The cover would remain on their own device, including in backups or audio
file tags, and display offline in the player and macOS Now Playing without periodic
replacement or deletion. We would keep search results temporary and would not
operate a public image mirror or distribute downloaded covers with the application.

Does your API agreement permit this workflow? Specifically, how do the storage,
freshness and adjacent-attribution provisions apply after a user saves a cover?
Can attribution in the artwork details/source view cover offline/system surfaces
that cannot show a clickable source link? If additional permission is required,
what agreement is available, and what underlying image-rights obligations remain?

### Acceptance of the permanent-artwork requirement

- Import a selected Discogs image, expire/delete its search cache, restart and go offline:
  the saved image remains byte-identical and visible.
- A changed or missing provider result cannot silently replace the saved cover.
- User replacement/removal and existing Undo retain their intended behavior.
- Transient previews still expire; saved-artwork rendering requires no provider
  token, network request or successful freshness check.
- The release checker accepts the explicit nonblocking artwork decision without
  claiming provider permission. This exception cannot waive the other gates.

## Owner requirement: permanent imported metadata and history

On 2026-09-15 the owner agreed that imported information such as an album year
must remain after search-cache expiry. This confirms the proposed policy: keep
successfully imported tags, saved CD filenames, maintenance reports and Undo
history until the user changes or removes them. Restart, offline use, provider
changes and lookup expiry must not clear or revert this saved information.

The separate metadata/report gate is now `owner-nonblocking`, bound to its own
[owner decision record](../publication/discogs-metadata-decision.json).
Provider permission remains unconfirmed. The decision supersedes earlier pending
G-IMPORT retention instructions. It preserves existing storage behavior and does
not require a migration. Temporary API responses/previews still expire, and new
imports still validate their evidence before saving.

Acceptance for the remaining integrated runtime/UI checks:

- Import a year, genre and track number, expire/delete lookup caches, restart and
  go offline: the saved values remain unchanged and available.
- Saved CD filenames and reports remain; cache cleanup does not rewrite or remove
  them. A report records the historical operation rather than a current lookup.
- User edits/removal and existing Undo retain their intended behavior.
- Each nonblocking retention gate requires its own unchanged, explicit decision;
  neither decision waives the other gate or any unrelated release requirement.

## Current primary terms

[Discogs API Terms of Use](https://support.discogs.com/hc/en-us/articles/360009334593-API-Terms-of-Use)
were retrieved on 2026-09-15; the page states Last Updated: May 27th, 2025.
The API Use and Restrictions section distinguishes CC0 catalogue data from restricted
data, including images. Its freshness provision prohibits display of content more
than six hours older than the service's information and limits caching/storage to
what is necessary for the application's service. Treating all downloaded covers as
CC0 or interpreting a response-cache timeout as permanent-import permission is not
supported by that distinction. Terms must be rechecked before release.

The Intellectual Property section requires adjacent “Data provided by Discogs.”
attribution linking to the page containing the data, and the following application
notice (also appropriate for usage documentation):

This application uses Discogs’ API but is not affiliated with, sponsored or endorsed by Discogs. ‘Discogs’ is a trademark of Zink Media, LLC.

## Technical contract

DiscogsFetchStamp records original acquisition wall time, sleep-inclusive continuous
time and boot identity immediately before an uncached request, after token acquisition.
Every contributing acquisition in DiscogsContentEvidence must have finite,
nonnegative elapsed time strictly below five hours on both clocks. The five-hour
cap is a conservative application margin, not a statement that the service's
freshness requirement is merely a storage TTL. Reboot or unavailable trusted clock
requires refetch; a cache write, copied value or image download does not renew age.

The current integrated D1–D7 slice provides canonical positive-ID release URLs,
mandatory acquisition stamps, shared stamped v2 search/CD response caches and
cache-bypassing HTTP sessions/requests. The evidence-required image API checks
before requests, after awaits/backoff and before returning bytes. These primitives
do not yet complete loaded UI expiry, transaction admission or long-running CD/rip
behavior. D8–D24 and actual rendered acceptance remain required.

A nil evidence value means ordinary local/non-Discogs data, not permission for a
Discogs-origin caller to discard provenance. Local artwork and generic MusicBrainz
cache behavior stay separate. No stored SwiftData columns or historical-provider
backfill are authorized in this remediation.

## Decision table

| Gate | Affected paths/content | Owner decision | Verification/release status |
| --- | --- | --- | --- |
| G-ARTWORK | User-selected permanent Discogs album covers, offline rendering and existing artwork Undo | Keep importing and saving covers permanently; unresolved provider interpretation must not block release | Owner-nonblocking; provider permission unconfirmed; exact decision is recorded separately from verified rights |
| G-IMPORT | Persistent genre/year/track-number imports, CD filenames/catalogue metadata, metadata Undo and maintenance reports; excludes the G-ARTWORK decision | Keep saved information until the user changes/removes it; search expiry must not delete or revert it | Owner-nonblocking with its own bound decision; provider permission unconfirmed |
| G-DISPLAY | NowPlayingCommandCenter and transient CD-derived metadata/artwork in system Now Playing surfaces lacking a source link | On 2026-09-15 owner approved original CD-Text/default metadata and no Discogs artwork in system Now Playing; attributed fresh Discogs content may remain inside Songbird | Product decision approved; D20 implementation and actual tests pending, release gate not yet verified |
| G-UI | About legal documents, manual/bulk Discogs review, year/genre, CD header/candidates, thumbnails, queue/player surfaces | On 2026-09-15 owner approved disposable local packaging, ad-hoc signing and launch with synthetic data only | V2 wiring and rendered evidence pending; no normal app/library, Developer ID, notarization or real-service credentials authorized |

## Required consumers and final boundaries

- DiscogsSearchView and DiscogsBulkReviewView: adjacent source links outside
  selection buttons; one expiry owner per surface; clear expired candidates,
  selections and loaded images; cancel tasks/invalidate generations; retain local
  search fields and stable album targets; explicit re-search, not silent reselection.
- DiscogsGenreReviewView, MissingYearView and LibraryItemActionHandler: preserve
  evidence through stable-ID, missing-only single/bulk actions and rollback.
- LibraryHealthMutationService: sample freshness inside the mutation boundary
  before preparation, assignment and save; one expired remote item rejects the batch.
  Existing local/nil evidence and Undo semantics do not inherit disposable-cache expiry.
- DiscogsAudioCDMetadataProvider and OpticalDiscService: shared strict Discogs cache
  rules despite generic long lifetimes, all contributing stamps, after-await and
  generation checks, service-owned expiry even with no CD view open, original
  CD-Text/default fallback without changing disc/device/sectors/playback identity.
- Track runtime CD presentation, LibrarySnapshot, ArtworkThumbnailService/View,
  ServicePane, queue/history, main/mini players and NowPlayingCommandCenter: provider-
  aware image references, cache keys and loaded-state expiry. Cache eviction alone
  cannot clear an already displayed CGImage. System metadata follows G-DISPLAY only.
- AudioCDRipCoordinator/AudioCDRipper: no stale filename/tag/art import after long
  awaits; retain completed audio files and provide recoverable refresh/reconfirmation
  or an explicitly selected fallback. Do not silently rename/delete completed files.
- RealLibraryRemediator: finish remote acquisition/download/normalization before
  mutations, preserve evidence across throttling/actor waits, and check again before
  assignment/save. Exercise synthetic stores only, never the normal library.

## Retention decisions and optional provider clarification

G-IMPORT and G-ARTWORK record separate nonblocking owner retention decisions.
The unsent artwork question above and further metadata clarification are optional
follow-up. Distinguish CC0 metadata, restricted images and API contractual terms;
do not label these decisions verified provider permission. Any future persisted
provenance or historical-data migration needs a separate approved ExecPlan.

## Disposable acceptance safety

Canned client/clock wiring must be restricted to the verified disposable testing
identity/profile. It must not load real tokens, fall back to real network access or
become a production network-bypass switch. Source-link activation is observed without
opening the user's normal browser or contacting the real service. Use only the
harness's returned app/profile/PIDs and synthetic fixtures; missing isolation or
permissions is a stop condition. No rendered acceptance has been performed yet.
