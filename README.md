# Songbird

> **Songbird 0.1.0 hobby test build:** Apple Silicon, macOS 14+, ad-hoc signed. Share the app with its matching source archive and checksums; see [build instructions](SOURCE_CODE.md). The owner approved retaining the Songbird name and bird artwork. Exact scope and evidence are in the companion release receipt and [release decisions](publication/release-gates.json). Source repository: [ajzrva-sys/songbird](https://github.com/ajzrva-sys/songbird).

A native macOS music player with a classic, library-first interface. Browse your own music, build playlists, and switch between a full library window and a compact mini player.

Built with SwiftUI, SwiftData, and a native buffered audio engine. This is a native Swift implementation inspired by the Songbird/Nightingale interface, not the legacy XUL application.

> **Development preview.** The local packager uses ad-hoc signing. Developer ID signing and notarization are outside this hobby-build pass.

## Features

- **Library browsing:** tracks, albums, artists, genres, recently added music, and play counts, with search and cascading filters.
- **Organization:** manual and rule-based smart playlists, favorites, ratings, a play queue, and M3U playlist export.
- **Playback:** native buffered local-file playback, gapless and crossfade controls, and a compact mini player.
- **Feathers:** classic and newer themes, including Blue Monday and Terminal, with theme-specific Dock icon choices.
- **Library Health:** review missing files, unavailable volumes, duplicate tracks, missing artwork, and incomplete metadata.
- **Metadata and artwork:** track-information editing and optional Discogs artwork/genre lookup; optional Last.fm scrobbling.
- **Folder management:** deliberate imports and scans, plus automatic watching for eligible local folders. Network folders use manual scans.

Recognized local-file extensions: `mp3`, `m4a`, `aac`, `flac`, `wav`, `aiff`, and `aif`. Playback of non-FLAC files uses the system audio APIs; a recognized extension does not guarantee every codec/container combination.

## Screenshots

The README gallery is pending recapture. Current bounded UI evidence is supplied with the release receipt; see [the screenshot notes](docs/screenshots/README.md).

## Requirements

- **macOS 14 or later** is the deployment target; macOS 14 runtime acceptance remains a separate release gate.
- **Apple Silicon** for the bundled dependencies as currently supplied. The aubio library is arm64-only, so this is not an Intel/universal build.
- **Xcode with its command-line tools selected.** The 2026-09-15 local release build used Xcode 26.6 and Apple Swift 6.3.3. The manifest's Swift tools version is 5.9; it is not a verified minimum for the entire current test suite.
- Bundled dependency sources support offline builds; set `SONGBIRD_OFFLINE_DEPS=1`. Discogs, Last.fm, and online CD metadata are optional network features.

## Build and run

From the repository root:

```sh
./build.sh
open ./Songbird.app
```

`build.sh` compiles release products, packages the runtime libraries and resources, and verifies the resulting app's ad-hoc signature. It **replaces the output `Songbird.app` bundle**; do not point it at an installation you need to preserve. Building does not itself launch the app.

For compilation without packaging or launch:

```sh
swift build -c release
```

The scripts and vendored dependencies must be included in your checkout. A local signature check is not Apple notarization. If macOS blocks a downloaded dependency, verify its source before granting a local exception; do not disable Gatekeeper globally.

## Development and testing

```sh
./check.sh quick
./scripts/validate-agent-harness.sh README.md docs/screenshots/README.md
```

`quick` runs the Swift package tests. See [TESTING.md](TESTING.md) for focused checks, audio Thread Sanitizer coverage, disposable UI testing, and manual release gates. The release receipt identifies current visual checks and earlier behavior coverage.

Useful starting points:

- [Architecture](ARCHITECTURE.md) — subsystem ownership and data flow.
- [Audio engine](AUDIO_ENGINE.md) — native playback and real-time constraints.
- [Documentation index](docs/.INDEX.md) — repository guidance and current work.
- [Screenshot capture notes](docs/screenshots/README.md) — provenance and reproduction.

## Current limitations

- **Physical-CD playback, ripping and eject were confirmed working by the owner.** AirPlay and the broader [audio hardware matrix](Tests/HardwareAudioMatrix.md) remain untested.
- **Local packaging is not a distribution release.** Developer ID signing, notarization, and a verified public release pipeline are not supplied by the current ad-hoc packaging flow.
- **Back up important music and library data before experimenting.** Metadata writeback can modify audio files; do not assume every editing operation is catalog-only.
- The README screenshot gallery and full usability/accessibility/device matrix are not complete.

## Licensing and acknowledgments

Copyright (C) 2026 Andrew Zimmerman. Authorized original application code and project-authored assets are licensed under GPL-3.0-or-later. See the full
[GPL](LICENSE), [project notice](NOTICE.txt), [license scope](docs/LICENSE_SCOPE.md),
[third-party notices](THIRD_PARTY_NOTICES.txt) and [corresponding-source status](SOURCE_CODE.md).
This program comes WITHOUT ANY WARRANTY. Third-party material retains its own terms;
the GPL-linked combined application is not presented as an MIT/BSD application.

- **aubio:** retained under its source headers' GPLv3-or-later terms, with full GPL,
  per-file notices, Ooura's author-site grant and other recovered author credits.
  Reviewed library outputs were adopted with verified hashes and retained backups.
- **libFLAC and libogg:** copyright and redistribution terms are in [their bundled notice](Vendor/FLAC/NOTICE.txt).
- **GRDB.swift:** retained at the pinned revision, with its root MIT notice,
  Rails-derived MIT notices and Swift-derived Apache/Runtime Exception notices.
  Production sources and the documented test-target-only manifest adaptation are
  supplied; fresh offline and OS-network-denied builds passed. See
  [the offline source instructions](docs/grdb-source-import.md).
- **Historical artwork and branding:** the project records Songbird/Nightingale asset lineage in [PARITY.md](PARITY.md). That history is not a substitute for asset-license verification and attribution.

The owner approved restoring the original bird logos and themed icons; see [the artwork decision](publication/artwork-decision.json) and [exact image provenance](Sources/Resources/asset-provenance.json). The images retain their applicable terms and are not represented as newly authored artwork. Still-excluded reference images and screenshots remain in [the retired-asset list](publication/retired-asset-hashes.json).

This application uses Discogs’ API but is not affiliated with, sponsored or endorsed by Discogs. ‘Discogs’ is a trademark of Zink Media, LLC.

[Discogs content policy](docs/DISCOGS_CONTENT_POLICY.md) describes temporary lookup expiry and permanent saved imports. Existing saved user covers/tags are not silently expired or migrated.
