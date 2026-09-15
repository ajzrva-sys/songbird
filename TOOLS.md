# Candidate Tools and Environment

The baseline was compiled with Xcode 26.6 (17F113), Apple Swift 6.3.3 on arm64 macOS.
Package.swift declares tools version 5.9 and macOS 14; that is not a verified minimum
compiler for every current test. The bundled aubio dylib is arm64-only.

GRDB.swift is pinned by Package.resolved. Initial resolution requires network access;
keep the lockfile in the public baseline. Do not update dependencies as a workaround.

`check.sh quick` invokes swift test. `build.sh` invokes compilation and destructive
replacement of its chosen app output via scripts/package-songbird.sh, including
signing. Avoid build.sh for a compile-only check. `scripts/rebuild-aubio.sh` replaces
a vendor binary after backing it up; do not run it without dependency work scope.
The audio fixture generator requires ffmpeg and rewrites fixtures/checksums.

Build products, caches, private usability reports, credentials, and old reference
apps are not publication inputs. The preparation logs and isolated scratch/home
live in a sibling verification directory, not in this repository.

Tests must use disposable data. Discogs/Last.fm credentials belong in Keychain;
MusicBrainz/Discogs/Last.fm network calls must be mocked or disabled for deterministic
tests. Do not print or commit real credentials. Optional migration fixture variables
must not point at an active user's store.

See [TESTING.md](TESTING.md), [the baseline record](docs/PUBLICATION_BASELINE.md),
and [the documentation index](docs/.INDEX.md) for exact scope and remaining gates.
