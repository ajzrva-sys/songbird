# GRDB production-source import

## Identity and scope

The opt-in offline dependency is GRDB.swift **v6.29.3**, commit
`2cf6c756e1e5ef6901ebae16576a7e4e4b834622`, from
<https://github.com/groue/GRDB.swift>. The tag spelling includes `v`.
The ordinary Songbird `Package.resolved` retains that revision and version;
normal builds still use the original remote dependency requirement, `from: "6.24.0"`.
Only the exact environment value `SONGBIRD_OFFLINE_DEPS=1` selects
`Vendor/GRDB.swift`. No Songbird target or test has been removed.

The import was independently copied from the clean verified checkout, not linked
or adopted from a SwiftPM build cache. Every upstream blob was reverified against
its recorded Git object ID before selection. The source-review evidence also
authenticated the GitHub `v6.29.3` tag at this commit. This is source identity
verification, not a cryptographic author-signature certification or legal clearance.

[The source inventory](../publication/grdb-source-inventory.json) records every
imported upstream path, Git blob/mode, original SHA-256/size, delivered
SHA-256/size/mode, supplemental notice origin, and every omitted upstream entry.
Imported regular files use upstream Git mode `100644` (filesystem `0644`), rather
than the verification checkout's read-only filesystem mode `0444`.

### Included

- All **164** Swift source files beneath upstream `GRDB/`, byte-identical.
- `GRDB/PrivacyInfo.xcprivacy`, byte-identical and still copied as a SwiftPM resource.
- `Sources/CSQLite/module.modulemap` and `shim.h`, byte-identical. These expose and
  link the SDK/system SQLite library; custom SQLite and Apple framework binaries
  are not bundled by this import.
- Upstream root `LICENSE` (Gwendal Roué MIT), byte-identical.
- Upstream `Package.swift`, with the one approved adaptation described below.
- Two supplemental notice files under `Vendor/GRDB.swift/Notices/`.

That is **169 upstream files** (168 unchanged, one adapted manifest) and two
supplemental notice files. No upstream runtime Swift source was modified.

### Omitted and why

The inventory enumerates **679 omitted upstream blob entries**, plus the separate
`SQLiteCustom/src` Git submodule entry at
`31e6aa66188e59616f062df77329d6ee9ee45929`. Its contents were not imported.
The omitted scope includes:

- All **385** upstream `Tests/` entries, including the declared `Betty.jpeg`,
  `InflectionsTests.json`, and `Issue1383.sqlite` resources. No separate rights
  grant for `Betty.jpeg` was established; approval specifically selected a
  production-only package instead of importing this fixture tree.
- All **47** entries in `GRDB/Documentation.docc/` (23 Markdown documents and
  24 image assets). They are documentation inputs, not production Swift code or
  the required privacy resource. Documentation building is not supported by this
  reduced import.
- Other documentation, images, examples, Xcode/CocoaPods/custom-SQLite integration,
  CI/configuration and upstream maintenance scripts outside the production
  SwiftPM subset. Upstream tests contain a symlink, which is omitted as well.
- Git metadata, gitlinks/submodule working trees, and generated build products.

This is complete for the retained **production SwiftPM targets** under the tested
macOS configuration, not a complete upstream development checkout, documentation
package, custom-SQLite distribution, or proof of all upstream platforms/options.

## Exact manifest adaptation

[The original manifest](../publication/grdb-upstream-Package.swift) preserves the
unmodified upstream bytes. [The patch](../publication/grdb-manifest.patch) removes
only the entire `.testTarget(name: "GRDBTests", ...)` declaration (upstream lines
59–80), including its excluded test helpers and resource list. The remaining
trailing comma is valid Swift. All production targets/products, platform and
language declarations, settings, default localization, resource declaration, and
environment-controlled branches are unchanged. The original manifest is evidence,
not the manifest used to build the reduced package.

In particular, the upstream `SPI_BUILDER=1` branch still introduces
`swift-docc-plugin`, and `SQLITE_ENABLE_PREUPDATE_HOOK=1` still changes definitions.
**Explicitly unset both for offline verification.** Selecting the local GRDB path
alone does not disable those upstream environment switches.

## Notices

- `Vendor/GRDB.swift/LICENSE`: exact upstream MIT notice,
  SHA-256 `b9ce5b40c859a62fa6998995a9d284565aba72e92ca7c655f64777948f885139`.
- `Notices/Inflections-MIT.txt`: exact first 43 source lines from
  `GRDB/Utils/Inflections+English.swift`, preserving both Gwendal Roué's
  2015–2023 MIT notice and David Heinemeier Hansson's 2005–2019 Rails-derived
  MIT notice. These notices also remain in the untouched Swift source.
- `Notices/Swift-Apache-2.0-with-Runtime-Exception.txt`: full authenticated
  <https://www.swift.org/LICENSE.txt> text, SHA-256
  `167beb36f181bd163c93c6feb45c68e5f9462fe1af55b278f7bfd1df20e673a3`.
  The embedded Apple Inc./Swift project author notices remain in
  `GRDB/Core/Cursor.swift` (2014–2018), `Record/EncodableRecord.swift` and
  `Record/FetchableRecord.swift` (2014–2020). Do not label these portions as
  Gwendal-only MIT or assume the runtime exception eliminates notice obligations
  for manually adapted source.

These copies deliver the source notices. Canonical root/app legal-resource
synchronization and rendered notice acceptance are separate integration work;
SwiftPM does not automatically package these supplemental notices into Songbird.

## Reproduce without dependency downloads

Prerequisites: macOS 14+, Xcode/Apple SDK and Swift toolchain capable of building
Songbird, system SQLite headers/library, and the separately reviewed Songbird C
bridge/vendor dependencies. The S6 experiment used Apple Swift 6.3.3 and Xcode
26.6 on arm64. It used the snapshot's unchanged existing FLAC/ogg/aubio libraries;
S6 does not establish their source-to-binary correspondence or authorize adoption.

Run from an independent full-source copy. Keep logs, HOME, store and scratch
outside the source payload. A new scratch directory must not contain dependency
checkouts or compiled objects from any earlier build:

```sh
(
RUN=$(mktemp -d /private/tmp/songbird-offline.XXXXXX)
mkdir "$RUN/home" "$RUN/test-root"
cp Package.resolved "$RUN/Package.resolved.before"
# SwiftPM can delete the now-unused remote pin. Restore only this exact before-copy.
trap 'cp "$RUN/Package.resolved.before" Package.resolved' EXIT
env -u SPI_BUILDER -u SQLITE_ENABLE_PREUPDATE_HOOK \
  -u SONGBIRD_STORE_FIXTURE -u SONGBIRD_V1_STORE_FIXTURE \
  HOME="$RUN/home" CFFIXED_USER_HOME="$RUN/home" \
  SONGBIRD_UI_TEST_ROOT="$RUN/test-root" SONGBIRD_UI_TESTING=1 \
  SONGBIRD_OFFLINE_DEPS=1 \
  swift build -c release --scratch-path "$RUN/scratch" > "$RUN/build.log" 2>&1
)
```

SwiftPM 6.3.3 actually removed `Package.resolved` during the local-only S6 build.
The isolated validation restored the exact saved before-bytes afterward; this
is a resolver side effect, not a changed ordinary pin. The subshell/trap above
keeps that preservation explicit even when a build fails. Never run such a restore
against a shared worktree being edited by someone else.

Preserve the ordinary `Package.resolved` bytes. Never replace its remote pin with
an offline-only generated lockfile or adopt any resolver-side change back into
the ordinary source tree. Verify the fresh scratch `workspace-state.json` selects
only the local GRDB path, logs contain no dependency fetch/update, and compiled
GRDB inputs come from this copy's `Vendor/GRDB.swift` directory.

The S6 experiment also completed a second fresh release build inside a macOS
`sandbox-exec` profile containing `(version 1) (allow default) (deny network*)`,
with new HOME, cache/config/security and scratch paths. A socket probe returned
`EPERM`, confirming network denial. The build used SwiftPM `--disable-sandbox`
only to avoid macOS rejecting nested sandbox application; the outer OS network
sandbox remained active for the build and its children. It compiled all 164
vendored Swift files plus SwiftPM's generated resource accessor, copied the exact
privacy resource, and produced a Songbird executable with GRDB symbols. Both
fresh builds had only a filesystem GRDB dependency and empty repository/checkout
directories, with no GRDB/docc fetch in the logs. This is not a network-disabled
runtime test of Songbird's online services.

The focused manifest/inventory regressions need no network or upstream checkout:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover \
  -s scripts/tests -p test_grdb_offline.py -v
```

Full Songbird tests retain the same disposable environment, with
`./check.sh quick --scratch-path "$RUN/test-scratch"`. Do not run the removed
upstream tests against the read-only verification checkout. A final combined
source archive rebuild, release receipt linking actual output hashes, legal
resource synchronization, other component source correspondence, signing/UI and
hardware acceptance remain separate release gates.
