# Songbird 0.1.0 — corresponding source and build

The companion `Songbird-0.1.0-source.tar.gz` contains this app's source, resources,
notices, build scripts and all four bundled dependency sources. Share it alongside
`Songbird-0.1.0-macOS-arm64.zip` and `SHA256SUMS`. There is no public download URL.
The accompanying release receipt identifies the exact archives and validation.

## Requirements

Apple Silicon Mac, macOS 14 or later, Apple command-line development tools with
Swift 6.3.3 (the tested toolchain), Python 3 and CMake. The Apple SDK/system
frameworks are supplied by the development tools. Intel/universal builds are untested.
Once these tools are installed, the following build needs no network downloads.

## Build the app

Extract the source into a new directory and run from that directory:

```sh
export SONGBIRD_OFFLINE_DEPS=1
swift build -c release -j 4
./scripts/package-songbird.sh "$PWD/Songbird.app"
```

This uses the included reviewed aubio, FLAC and ogg libraries and compiles the
included GRDB 6.29.3 source. Packaging produces an ad-hoc signed app, with version
0.1.0/build 1. It does not install, launch or notarize the app.
SwiftPM may remove the unused remote `Package.resolved` in offline mode; this does
not affect the vendored build. Preserve the archive if you want its original bytes.

## Rebuild every bundled dependency

From a fresh extracted copy, before the Swift build above:

```sh
SOURCE=$(pwd -P)
WORK=$(mktemp -d /private/tmp/songbird-rebuild.XXXXXX)
./scripts/rebuild-aubio.sh --source-dir "$SOURCE/Vendor/aubio/src" \
  --output-dir "$WORK/aubio-output" --evidence-dir "$WORK/aubio-evidence"
./scripts/rebuild-flac-ogg.sh --source-dir "$SOURCE/Vendor/FLAC/source" \
  --output-dir "$WORK/flac-ogg-output" --evidence-dir "$WORK/flac-ogg-evidence"

./scripts/rebuild-aubio.sh \
  --install-reviewed-output "$WORK/aubio-output/libaubio.5.dylib" \
  --expected-sha256 "$(shasum -a 256 "$WORK/aubio-output/libaubio.5.dylib" | awk '{print $1}')" \
  --backup-dir "$WORK/old-aubio"
./scripts/rebuild-flac-ogg.sh \
  --install-reviewed-output "$WORK/flac-ogg-output/libogg.0.dylib" \
  --expected-sha256 "$(shasum -a 256 "$WORK/flac-ogg-output/libogg.0.dylib" | awk '{print $1}')" \
  --backup-dir "$WORK/old-ogg"
./scripts/rebuild-flac-ogg.sh \
  --install-reviewed-output "$WORK/flac-ogg-output/libFLAC.14.dylib" \
  --expected-sha256 "$(shasum -a 256 "$WORK/flac-ogg-output/libFLAC.14.dylib" | awk '{print $1}')" \
  --backup-dir "$WORK/old-flac"
```

These commands intentionally replace only the libraries in your extracted copy,
keeping backups and build receipts under `$WORK`. They build FLAC 1.5.0, ogg 1.3.6,
and the retained aubio snapshot using its supplied minimal CMake recipe. GRDB is
built by SwiftPM. Different toolchain paths, Mach-O identifiers and signing can
change output hashes; this is a source rebuild, not a promise of bit-identical apps.
See `docs/vendor-rebuilds.md` for configuration and `publication/corresponding-source.json`
for exact source inventories and identities.

## Checks and notices

Use disposable data when testing:

```sh
TEST_WORK=$(mktemp -d /private/tmp/songbird-tests.XXXXXX)
mkdir -p "$TEST_WORK/home" "$TEST_WORK/profile"
HOME="$TEST_WORK/home" CFFIXED_USER_HOME="$TEST_WORK/home" \
  SONGBIRD_UI_TEST_ROOT="$TEST_WORK/profile" SONGBIRD_UI_TESTING=1 \
  SONGBIRD_OFFLINE_DEPS=1 ./check.sh quick -j 4
python3 -m unittest discover -s scripts/tests
```

The app's About → **License, Notices & Source…** window reads all four documents
from its own bundle and works offline. `LICENSE`, `NOTICE.txt`,
`THIRD_PARTY_NOTICES.txt` and this file are canonical; their exact bundled copies
are in `Sources/Resources/Legal`. Existing component-specific licenses remain in
force. Keep the app and matching source together when sharing this hobby test build.
