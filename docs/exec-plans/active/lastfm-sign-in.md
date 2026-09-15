# Simple Last.fm sign-in

## Purpose / Big Picture

Replace Settings' developer credential/password form with browser sign-in. Existing
sessions and scrobbling remain compatible. People using a configured build do not
register their own API application. This work does not change playback or libraries.

## Progress

- [x] 2026-09-15: Compared current and preserved source; both use the same manual form.
- [x] 2026-09-15: Checked Last.fm's desktop authentication documentation.
- [x] 2026-09-15: Implemented browser token/session exchange, Settings, and packaging configuration.
- [x] 2026-09-15: Isolated tests, full quick suite, optimized build, and packaging passed.
- [x] 2026-09-15: Owner created the replacement registration; configured and installed the build.
- [x] 2026-09-15: Last.fm accepted a signed application-token request. User approval/scrobbling remains a manual acceptance check.

## Surprises & Discoveries

The starting source/package supplied no application credentials. The preserved
checkout has moved to the sibling songbird-old directory. After signing in, the
owner's existing registration was found, but Last.fm did not display its shared
secret and a targeted noninteractive Songbird Keychain lookup found no saved key.
The owner created a replacement registration and authorized configuring the build
from its confirmation page. The new app credentials are stored privately outside
the repository. The normal library and old registration remain unchanged.

## Decision Log

- Use Last.fm's documented desktop flow: request token, browser approval, session
  exchange. Store the session using the existing credential store. No password form.
- Reuse stored API credentials where present; otherwise use credentials supplied
  when packaging. Never silently substitute another application's API identity.
- Keep missing app configuration explicit. A button alone cannot authenticate an
  unconfigured build. The owner supplied the replacement registration on 2026-09-15.
- Preserve build configuration outside Git so ordinary local rebuilds retain it.

## Context and Orientation

`Sources/Integrations/LastFMClient.swift` owns signing, authentication, and posts.
`Sources/Views/SettingsView.swift` owns the existing form. Credential persistence
and legacy migration are in `SongbirdCredentialStore.swift`. Tests inject in-memory
storage and canned HTTP responses. `scripts/package-songbird.sh` assembles/signs apps.

## Plan of Work

Add browser authentication with injectable network/defaults/configuration inputs.
Replace the Last.fm tab with a dedicated view that displays connection state,
browser sign-in, completion/cancellation, and sign-out. Add a packaging helper for
build-time application credentials, with no credential values in source or logs.
Test success, pending authorization, errors, cancellation, and retained sessions.

## Concrete Steps

Work only in the publication repository. Preserve before-images and evidence under
the external `/private/tmp/songbird-lastfm-*` work directory. Run focused tests and
`./check.sh quick -j 4` using isolated HOME and SONGBIRD_UI_TEST_ROOT. Build with
`SONGBIRD_OFFLINE_DEPS=1 ./build.sh <external app path>`. Refresh TESTING and manifest.
Install only a configured, verified package, retaining the previous installed app.

## Validation and Acceptance

Settings must have no username/password/API-key/secret inputs. A configured build
opens Last.fm for normal sign-in and approval, then stores the returned session and
username. Existing sessions continue to work. Tests use no live credentials or
network. Real browser approval/scrobbling remains a manual check until configured.

## Idempotence and Recovery

Failed/cancelled authorization must preserve existing saved credentials and session.
Pending tokens live only in memory. Sign-out removes the session, retaining app
configuration. Backups allow restoring source or installed app without library edits.

## Artifacts and Notes

References: https://www.last.fm/api/desktopauth,
https://www.last.fm/api/show/auth.getSession.

## Interfaces and Dependencies

Existing LastFMClient public API and credential keys remain compatible. New state
and browser-authentication entry points are shared with the Settings view. Foundation,
SwiftUI, AppKit, and the current credential store suffice; no dependencies or schema changes.

## Outcomes & Retrospective

The configured app is installed with a backup. Eleven focused authentication tests,
12 existing credential tests, 109 Python checks (two opt-in skips), the full quick suite (296 XCTest
cases, two expected skips, and 334 Swift Testing cases), and signed packaging passed.
The full run preceded two test-only additions, which passed in the final focused run.
Last.fm accepted the configured app's token request. UI appearance, real account
approval, and real scrobbling are manual acceptance, not claimed automated passes.
The account registration/setup was completed once by the owner. Listeners now use
normal browser approval. Logs/receipts are retained outside the source tree.
