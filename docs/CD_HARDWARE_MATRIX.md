# Audio CD release gate

Raw CD support is not release-ready until every required row passes for both a direct signed build and a signed sandbox candidate. Run `CDSandboxProbe` with an inserted audio disc first; `TOC_DENIED` or `SECTOR_DENIED` fails App Store parity and makes direct distribution the supported CD build.

| Build | Drive | Disc | Discover | TOC | Sector read | Play/seek | Gapless | Sleep/wake | Eject/remove | Result |
|---|---|---|---|---|---|---|---|---|---|---|
| Direct | Apple USB SuperDrive (firmware 2.03) | Pressed audio CD, 4 tracks | Pass | Pass | Pass (2,352 bytes) | Pending | Pending | Pending | Pending | Partial pass |
| Direct | Third-party USB drive | Pressed audio CD | Pending | Pending | Pending | Pending | Pending | Pending | Pending | Pending |
| Direct | Either | Mixed-mode CD | Pending | Pending | Pending | Pending | Pending | Pending | Pending | Pending |
| Sandbox | Apple USB SuperDrive | Pressed audio CD | Pending | Pending | Pending | Pending | Pending | Pending | Pending | Pending |
| Sandbox | Third-party USB drive | Pressed audio CD | Pending | Pending | Pending | Pending | Pending | Pending | Pending | Pending |

## 2026-07-31 probe notes

- Direct release probe passed against `/dev/rdisk4`: 4 TOC tracks, lead-out sector 58,347, and one complete 2,352-byte CDDA sector.
- An ad-hoc signed command-line probe with App Sandbox and USB entitlements terminated at process launch with signal 5 (`exit 133`) before producing probe output. This does **not** prove sector denial; repeat the sandbox row using the real Apple Development/App Store signing identity and app bundle before making the parity decision.

Also verify two-drive isolation, paused eject, removal during preload, damaged-media errors, VoiceOver, Voice Control, Full Keyboard Access, Larger Text, Increase Contrast, and light/dark appearances.
