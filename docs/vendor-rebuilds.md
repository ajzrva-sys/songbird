# Controlled vendor rebuilds

These are **replacement-source recipes**, not a recovered provenance claim for the
pre-existing dylibs. A successful build is not adoption, legal clearance, or release
approval. The supported output profile is **arm64, macOS 14.0+**. Selecting this
profile deliberately narrows the formerly universal FLAC/ogg pair; aubio was already
arm64-only. Do not advertise Intel support from these outputs.

## Source inputs

- aubio: retained upstream files match commit
  `ad5cf975aed08cc4562dd008cf9f83b12b82ffb8` from the vendor-designated GitHub mirror.
  The authenticated snapshot archive SHA-256 is
  `00d644c832cb13979e59abd11b7849f8f9a3e2a8ed6a6faefb83f7a7d135b759`.
  `Vendor/aubio/src` contains 132 unchanged upstream files: the complete upstream
  `src/` tree and four root build/version/license files. The 242 omitted upstream
  files are outside `src/` (Python, tests, docs, examples, scripts and root files).
  Use Songbird's existing `scripts/aubio-cmake` recipe, not the reduced tree's root
  CMakeLists, which references omitted programs/tests. The source version is
  `0.5.0-alpha`; Songbird's explicit dylib version is `5.4.8`, soversion `5`.
  No upstream aubio source or existing bridge headers are modified by this work.
- FLAC **1.5.0**:
  <https://downloads.xiph.org/releases/flac/flac-1.5.0.tar.xz>, SHA-256
  `f2c1c76592a82ffff8413ba3c4a1299b6c7ab06c734dee03fd88630485c2b920`.
- libogg **1.3.6**:
  <https://downloads.xiph.org/releases/ogg/libogg-1.3.6.tar.xz>, SHA-256
  `5c8253428e181840cd20d41f3ca16557a9cc04bad4a3d04cce84808677fa1061`.

The Xiph archive hashes were checked against <https://xiph.org/downloads/>.
`publication/vendor-source-imports.json` enumerates every regular imported file,
SHA-256, size and safe delivered mode, with official URLs and archive hashes. FLAC
has 847 files; ogg has 135. No regular archive member is omitted or content-patched.
Release-root names are mapped to `Vendor/FLAC/source/flac` and `ogg`. Original
archive modes are retained in each entry's archive_modes map; the candidate uses
0644/0755 according to executable bits instead of importing 125 world-writable
0666/0777 modes. This explicit metadata transformation leaves every source byte
unchanged and makes build admission check the actual safe delivered inventory.
Archive paths/types were checked before extraction; no links or special files were
imported. The rebuild verifies exact FLAC/ogg inventory membership, bytes and modes
before invoking build tools.

All original per-file notices remain. FLAC's complete source includes
`COPYING.Xiph`, `COPYING.GPL`, `COPYING.LGPL`, and `COPYING.FDL`; the complete source
is not uniformly BSD. Ogg retains `COPYING` and its per-file attributions, including
the CRC derivation in `src/framing.c`. These imports do not replace the separate
canonical/app notice review or resolve historical binary correspondence.

## Non-destructive commands

Prerequisites: macOS with an installed Apple developer toolchain, Python 3 and
CMake. These scripts were exercised with CMake 4.4.3 and Apple clang; exact local
versions belong in the generated external receipt. No system package installation,
network download, app packaging, app signing, or app launch is performed by either
rebuild script.

From the repository root, use **canonical absolute paths** (no symlink ancestors,
`..`, relative names or normalization aliases):

```sh
SOURCE=$(pwd -P)
RUN=$(mktemp -d /private/tmp/songbird-vendor.XXXXXX)
./scripts/rebuild-aubio.sh --validate-options \
  --source-dir "$SOURCE/Vendor/aubio/src" \
  --output-dir "$RUN/aubio-output" --evidence-dir "$RUN/aubio-evidence"
./scripts/rebuild-aubio.sh \
  --source-dir "$SOURCE/Vendor/aubio/src" \
  --output-dir "$RUN/aubio-output" --evidence-dir "$RUN/aubio-evidence"
./scripts/rebuild-flac-ogg.sh --validate-options \
  --source-dir "$SOURCE/Vendor/FLAC/source" \
  --output-dir "$RUN/flac-ogg-output" --evidence-dir "$RUN/flac-ogg-evidence"
./scripts/rebuild-flac-ogg.sh \
  --source-dir "$SOURCE/Vendor/FLAC/source" \
  --output-dir "$RUN/flac-ogg-output" --evidence-dir "$RUN/flac-ogg-evidence"
```

Output/evidence destinations must not exist; their parents must already exist.
They must be outside the script's project root and source tree, noncolliding with
each other. A repeat requires new paths; partial/failed evidence is retained, never
silently deleted. Validation is read-only and does not discover/invoke compilers.
Missing arguments fail closed. There is no overwrite-vendor default. The aubio
source argument may be omitted to select the script-root's retained source; the
FLAC/ogg source argument is mandatory and names the parent of `flac/` and `ogg/`.

The small shell entry points share `scripts/vendor_rebuild.py` so canonical path,
link/hardlink rejection, exact argv capture, hashing and adoption checks have one
tested implementation instead of two divergent shell implementations. Build tools
are trusted operator-selected tools, not a sandbox for untrusted build scripts.

## Effective recipe and receipts

The runner fixes Release, arm64, deployment target 14.0, Unix Makefiles, Apple
clang/make and the SDK returned by `xcrun`. It enables compile-command export and
disables user/system package registries and CMake environment-prefix discovery.
Child environments are explicitly constructed: caller CFLAGS, CPATH, LIBRARY_PATH,
SDKROOT, DYLD variables, CMAKE overrides and package-discovery settings are not
inherited. Builds use a fresh evidence-local home, temporary directory and empty
pkg-config directory. Source/config/script hashes, actual tool versions, effective
argv/environment, command exits and complete command logs are retained.

Aubio uses its unchanged custom standard-header config and compiles the retained C
sources. Optional host codec/FFT dependencies remain disabled. Its final install
ID is `@rpath/libaubio.5.dylib`. `CMAKE_BUILD_WITH_INSTALL_NAME_DIR=ON` uses the
recipe's existing `@rpath` install directory at link time, avoiding an unnecessary
post-link ID mutation.

Ogg is built and staged first with shared libraries ON, framework/testing/docs and
pkg-config/CMake module installation OFF. FLAC uses shared libraries and Ogg ON;
C++ libraries, programs, examples, tests, docs, manpages and package-config
installation OFF; multithreading, fortify and stack protector ON. Its configure
argv explicitly pins `OGG_INCLUDE_DIR` to the new stage's include directory and
`OGG_LIBRARY` to that stage's `lib/libogg.dylib`. `PKG_CONFIG_EXECUTABLE` is
`/usr/bin/false`, with empty pkg-config search paths. Cache entries, the compile
database, the exact link command and staged/output ogg hashes are checked before
FLAC compilation. Host Homebrew/local package paths in compile/link commands fail
the build rather than being tolerated.

**Verified recipe correction:** FLAC 1.5.0 unconditionally configures auxiliary
`getopt` even with programs OFF. Its optional `find_package(Intl)` selected a host
gettext header in the first controlled attempt. The runner now adds
`-DCMAKE_DISABLE_FIND_PACKAGE_Intl=ON`, which disables an optional dependency not
needed by libFLAC. This correction was recorded before rerunning; no upstream
source was patched and the first attempt was not counted as a pass.

Each evidence directory retains `receipt.json`, `source-inputs.json`,
`environment.json`, `toolchain.json`, `commands.jsonl`, numbered command logs and
complete generated build/stage directories. These include `CMakeCache.txt`,
`compile_commands.json`, generated `config.h` (and ogg `config_types.h`), compiler
configuration logs and link commands. Install-stage receipts inspect original build
and staged dylibs before/after CMake installation; this captures FLAC's build-rpath
removal, not just explicit `install_name_tool -id` calls. Final output receipts
retain before/after hashes, install IDs, dependencies, architectures and deployment
load commands, including when no ID edit was necessary. Local receipts contain
machine paths and must stay outside the public source payload.

## Tests and adoption boundary

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover \
  -s scripts/tests -p 'test_rebuild_*options.py' -v

# Actual builds: create a fresh parent; its four child destinations must not exist.
TEST_RUN=$(mktemp -d /private/tmp/songbird-vendor-tests.XXXXXX)
SONGBIRD_REBUILD_RUN="$TEST_RUN" PYTHONDONTWRITEBYTECODE=1 \
  python3 -m unittest discover -s scripts/tests -p 'test_rebuild_*options.py' -v
```

Without the integration environment variable, the two real-build tests explicitly
skip; option/source tests still run. With a fresh integration root, both real-build
tests run and retain actual outputs/evidence. Option/adoption tests use disposable
script-root projects with **sentinel bytes**, never repository dylibs.

Adoption is a **separate, approval-gated operation**, not a build option. Only after
an owner reviews the exact output hash and regression receipts may an operator use
`--install-reviewed-output FILE --expected-sha256 HASH --backup-dir NEW_DIRECTORY`.
Do not combine it with source/output/evidence arguments. Both FILE and the new backup
must be external and noncolliding. For FLAC/ogg the input basename selects only
`libFLAC.14.dylib` or `libogg.0.dylib`; each needs its own fresh backup directory.
The operation preserves the previous bytes, verifies them, atomically replaces only
the script-root target and reads back the exact installed hash. `--validate-options`
also works with adoption arguments without writing. A hash match is not human
approval. **S7 adoption was explicitly authorized and completed on 2026-09-15; the exact three reviewed hashes are installed, with external backups.**

Before any S7 adoption, use a separate owned source snapshot with preserved previous
binaries and exact reviewed copies. Run the focused BPM/native-backend/tag-writer
filter, full quick, optimized compilation and audio TSan with isolated HOME,
CFFIXED_USER_HOME and a distinct SONGBIRD_UI_TEST_ROOT plus SONGBIRD_UI_TESTING=1;
leave real-store fixture variables unset. Inspect `test-audio-tsan.sh`: it uses the
current package's default `.build` and does not forward scratch options, so it must
run only from the disposable source snapshot. Verify actual dynamic-loader paths
and hashes, native/Ogg FLAC decoding and metadata, not just compilation. These tests
do not establish app packaging/signing, UI rendering, hardware, or release readiness.
