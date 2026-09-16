# Sidebar artwork and stable local signing

## Purpose / Big Picture

Keep sidebar art in a compact, padded footer clear of navigation. Preserve macOS
Keychain authorization across local app updates with a stable signing certificate.
No user credentials, media, or normal library are read by verification.

## Progress

- [x] 2026-09-16: traced edge-to-edge artwork and unclipped scrolling region.
- [x] 2026-09-16: verified installed ad-hoc designated requirement is a changing code hash.
- [x] 2026-09-16: a disposable self-signed identity signs and verifies without changing trust settings.
- [x] 2026-09-16: added compact footer and configurable package signing.
- [x] 2026-09-16: 50 focused Swift tests, full 324 XCTest (two expected skips) and 343 Swift Testing tests passed; 114 Python tests (two expected skips) passed.
- [x] 2026-09-16: two differently compiled certificate-signed probes accessed one synthetic Keychain item with UI disabled; the ad-hoc control was denied.
- [x] 2026-09-16: optimized build/package passed (82.90 s), with certificate-bound app identity.
- [x] 2026-09-16: disposable UI shows full padded artwork at normal and 520-point heights and navigation scrolling above the footer.
- [x] 2026-09-16: installed verified 44-entry package; prior app retained as Songbird-20260916T080259Z.app.
- [x] 2026-09-16: partial UI report and build/signing/install receipts stored externally; publication checks recorded with final source commit.

## Surprises & Discoveries

No existing signing identity is available. The temporary signing keychain must be
in the user's keychain search list even when codesign receives --keychain. No root
trust or broad credential-access change is required. The certificate's default
designated requirement binds both the identifier and exact certificate hash.
The first UI preparation exposed an outdated parity assumption: signed library
bytes differ with CMS signing time. Parity now verifies both sealed apps, compares
library requirements, strips signatures from temporary copies and compares all
remaining library bytes. The runner's cleanup also used zsh's read-only status
variable; it now uses runner_exit_status so preparation failures clean up correctly.

## Decision Log

- Keep a 160-point maximum cover with 12-point padding, separate divider and
  navigation clipping. Short windows retain 300 points of navigation or hide art.
- Add optional local code-signing.json; unconfigured builds remain ad-hoc.
  Configured failures stop packaging rather than silently changing identities.
- Keep signing private material outside the repository in a private build keychain.
  This is local signing, not Developer ID distribution or notarization.
- Existing credential ACLs may require one final Always Allow approval for the new
  identity. Do not automate that prompt or weaken access controls.

## Context and Orientation

ServicePaneView/PlayerWindowMetrics own the footer. package-songbird.sh owns nested
signing; signing_config.py resolves the optional identity. Credential storage stays
unchanged. Starting revision: 8ba317a, clean songbird-public checkout.

## Plan of Work

Adjust layout and signing, test configuration failures and constrained geometry,
prove two different signed executables share identity and synthetic Keychain access,
then build, render in the disposable harness and install with backup.

## Concrete Steps

In /Users/aji/project/songbird-public run isolated ./check.sh quick -j 4,
python3 -m unittest discover -s scripts/tests, offline ./build.sh and bounded
scripts/ai-usability audit. Verify publication development/index, gates and harness.

## Validation and Acceptance

No navigation painted over the footer, full image visible with margins. Two changed
test binaries retain a certificate-bound requirement and read their synthetic item
with authentication UI disabled. An unrelated signature cannot satisfy that
requirement. No automated claim about the user's real Last.fm credential ACL.

## Idempotence and Recovery

Reuse the same certificate; never generate one per build. Preserve prior installed
app. Configured signing errors abort. Keep normal credentials/library unchanged.

## Artifacts and Notes

Work: /private/tmp/songbird-sidebar-signing-06ys5w3e.
External evidence: /Users/aji/project/songbird-public-verification/sidebar-signing-20260916.
Apple reference: https://developer.apple.com/library/archive/technotes/tn2206/_index.html

## Interfaces and Dependencies

No dependency, schema, audio or authentication protocol changes. Optional
SONGBIRD_SIGNING_CONFIG and SONGBIRD_SIGNING_IDENTITY select package signing.

## Outcomes & Retrospective

Owner correction after this pass: the requested appearance is edge-to-edge artwork
without dark borders or padding. The compact padded layout recorded below is
superseded; current correction evidence is recorded at the top of TESTING.md.
Signing behavior remains as verified here.

Installed in /Applications/Songbird.app with the same version and Last.fm application
configuration. Builds on this Mac now use a persistent certificate; synthetic
update access passed with authentication UI disabled, and an unrelated signature
was denied. Existing real credentials may still need one final Always Allow grant
per item when switching from ad-hoc signing. No real credentials or system trust
settings were changed. The normal app was not relaunched automatically.

The bounded UI check (run 20260916T080048Z-62583) confirms the requested layout at
normal and short heights, including scrolling to Play Queue. It is not a broad
usability pass. The ambiguous global Pause selector was resolved by scoping the
action to the Songbird window. The disposable app/broker were stopped.
Audio TSan, hardware, real-account ACL migration and notarization were not tested;
no corresponding subsystem was changed. All code and targeted harness checks passed.
