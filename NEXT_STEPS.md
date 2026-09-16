# Candidate next steps

## Pause and album artwork

Immediate Pause, shared album covers, background database readers and the menu-focus
loop fix are installed; see the [completed plan](docs/exec-plans/completed/pause-album-artwork.md).
**PERF-ALBUM-250:** continue reducing the measured 0.78–0.80 s menu-to-stable-album
transition toward the 250 ms target. The sustained multi-second freeze is fixed;
real-storage and audible Pause timing remain to be measured.

## Playback responsiveness

Playback preparation, preloading, seeking and decoder cleanup now avoid blocking
the UI on file I/O. Tests/TSan passed and the optimized build is installed; see the
[performance record](docs/exec-plans/completed/playback-responsiveness.md). Real-world
storage and audible-onset measurements remain outside this completed pass.

## Last.fm sign-in

Browser sign-in and build-time application configuration are implemented and
installed; see the [implementation record](docs/exec-plans/active/lastfm-sign-in.md).
The owner created the replacement registration. Real account approval/scrobbling
is left to the normal user sign-in flow.

## Ready-to-share implementation

The owner authorized the complete [hobby build plan](docs/exec-plans/active/ready-to-share.md)
on 2026-09-15, including adoption of the three reviewed libraries. About/notices,
CD foundations and surfaces, safe rip recovery, conservative system Now Playing,
and source-component validation are integrated. The combined checks, ad-hoc package, bounded disposable smoke and three remaining
technical gates pass. The sealed archive and its offline rebuild result are identified
in the companion RELEASE-RECEIPT.json; see that plan for actual acceptance.

Keep Songbird, Discogs importing, permanent saved artwork/tags/filenames/reports
and existing Undo. Naming is approved; separate privacy/contact review is waived.
Those decisions remain nonblocking and do not claim provider permission.

Work only in this publication candidate and disposable test roots. The original
checkout and normal library are outside this work. The owner confirmed physical-CD
playback, ripping and eject. AirPlay remains untested.

## GitHub publication

The owner authorized the initial source commit and push to the public repository
[ajzrva-sys/songbird](https://github.com/ajzrva-sys/songbird) on 2026-09-15.
Use the selected publication payload on `main`; preserve the separate development
checkout and local app/source archives. Earlier local-only instructions are superseded.

## Later, only if requested

Uploading app binaries as a GitHub Release, Developer ID signing and notarization
remain separate follow-ups. The current app is an ad-hoc signed hobby test build for Apple
Silicon/macOS 14+. Keep its matching source archive and checksums alongside it.

## History

[Publication baseline](docs/exec-plans/completed/publication-baseline.md) records the
original 537-file preparation. The [earlier remediation plan](docs/exec-plans/active/release-licensing-remediation.md)
retains dated receipts and implementation detail; its old pause and unanswered S7
request were superseded by the owner's complete implementation authorization.

## Bird artwork follow-up

Owner-approved restoration of the existing bird logos and themed icons is included
in [the handoff plan](docs/exec-plans/active/ready-to-share.md). Keep exact image
provenance and ordinary notices; do not re-open the accepted artwork decision.
