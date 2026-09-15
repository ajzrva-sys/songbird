# Vendor source review

Review date: 2026-09-15. This records source identity and notices, not permission to
publish a binary or a claim that the existing vendor binaries came from these inputs.
All four entries in [corresponding-source.json](../publication/corresponding-source.json)
remain blocked on final source/archive and delivered-output acceptance. GRDB's
production import and offline build evidence is now verified as described below;
this does not verify the existing C vendor binaries.

## Evidence and transport

[The source audit](../publication/vendor-source-audit.json) records downloaded URLs,
HTTPS/TLS results, real SHA-256/size identities, all retained aubio source/header rows,
and every upstream omission. These are authenticated HTTPS source observations, not
cryptographically signed author-release verification. The parent independently rehashed
all 12 downloads, compared the retained source against the immutable aubio archive,
and reproduced the Ooura author-file identity. Local logs/archives remain outside
this publication tree; no private paths, Git cache, old images or credentials were imported.

## aubio

The official [aubio download page](https://aubio.org/download) designates the GitHub
mirror. The immutable source snapshot at
[ad5cf975aed08cc4562dd008cf9f83b12b82ffb8](https://codeload.github.com/aubio/aubio/tar.gz/ad5cf975aed08cc4562dd008cf9f83b12b82ffb8)
has archive SHA-256 00d644c832cb13979e59abd11b7849f8f9a3e2a8ed6a6faefb83f7a7d135b759.
All 132 retained Vendor/aubio/src files and 11 imported bridge headers match it byte
for byte. The audit enumerates 242 omitted upstream files; none is in upstream src/.
This identifies an upstream-equivalent retained source snapshot, not which commit
was originally downloaded or how the existing binary was produced.

The reduced source omits upstream examples/tests referenced by its root CMakeLists.
Use scripts/aubio-cmake instead. Its dylib version 5.4.8 is not the source VERSION
file's 0.5.0-alpha label or evidence of a source release tag. Local bridge/build inputs
retain their own inventory. Non-destructive rebuild, evidence capture and approved
binary adoption are separate. The new non-destructive rebuild/evidence path has
passed parent checks and actual-library regressions; candidate adoption remains
unapproved. The old overwrite-vendor default was replaced, not run against real inputs.

### Ooura and other aubio attributions

The [author-site license](https://www.kurims.kyoto-u.ac.jp/~ooura/fft.html) gives the
Takuya OOURA 1996–2001 credit and permission to use, copy, modify and distribute,
including commercial use, with a reference to the package when modifying. The
[author package](https://www.kurims.kyoto-u.ac.jp/~ooura/fft.tgz) SHA-256 is
52bb637c70b971958ec79c9c8752b1df5ff0218a4db4510e60826e0cb79b5296.
Its older archive readme limits its redistribution wording to the ORIGINAL package;
the broader permission is from the author website and is not misattributed to that readme.

Reversing aubio's documented prologue/type/cast/prefix/math-macro adaptations gives
exact author fft8g.c SHA-256
0844c1b338c1db15858f9feb8c166dffb2696a998a0b59aeaf13dce84eb4c5fc.
The retained adapted file SHA-256 is
da70d1cd4cc9bd1ba387cdf2c3409cdcd4cc0af7e65917896a08b9b3e128c109.
The grant, reference and adaptation notice are delivered in
[THIRD_PARTY_NOTICES.txt](../THIRD_PARTY_NOTICES.txt), along with the retained Mario
Lang/Paul Brossier notice shared by pitchfcomb.c and pitchschmitt.c. Other per-file
copyright/date notices remain untouched; this material is not Andrew Zimmerman-owned
original FFT source.

## FLAC and ogg: controlled replacement, not recovered history

The current FLAC binary embeds reference libFLAC 1.5.0 20250211. Both of its
architecture slices record ogg dependency current version 0.8.5; the supplied ogg
slices identify themselves as 0.8.6. This is an unexplained build/supply difference,
not an automatic ABI failure and not a source-release pin. The original supplier
chain was not found in the bounded vendor/build/package inputs.

The owner approved source import/build from these exact official archives:

- [FLAC 1.5.0](https://downloads.xiph.org/releases/flac/flac-1.5.0.tar.xz), SHA-256
  f2c1c76592a82ffff8413ba3c4a1299b6c7ab06c734dee03fd88630485c2b920.
- [libogg 1.3.6](https://downloads.xiph.org/releases/ogg/libogg-1.3.6.tar.xz), SHA-256
  5c8253428e181840cd20d41f3ca16557a9cc04bad4a3d04cce84808677fa1061.

Both hashes were checked against the [official Xiph listing](https://xiph.org/downloads/).
The selected output architecture is arm64/macOS 14+, knowingly narrowing the currently
universal FLAC/ogg pair to the app's aubio-supported architecture. S7 adoption remains
separate and unapproved. Build commands were recorded in the active plan before work.
The FLAC finder must receive explicit controlled OGG_INCLUDE_DIR and OGG_LIBRARY,
not merely Ogg_DIR or a broad prefix that could select a host installation.

Preserve existing notices and the exact approved sources' notices. FLAC's complete
source includes BSD, GPL, LGPL and FDL scope; do not call its entire archive BSD.
The existing combined notice is not byte-identical to the approved archives' license
texts and does not prove historical binary provenance. Those exact source notices
must be included when the reviewed source import is integrated.

The source import is now integrated: all 847 FLAC and 135 ogg regular archive files,
with exact bytes and notices. Original archive modes remain in the import ledger;
125 unsafe 0666/0777 modes were normalized to 0644/0755 before candidate writes.
Parent rebuilds passed all ten option/source/actual-build tests. The corrected
FLAC recipe disables optional host Intl discovery; it still validates exact
controlled ogg include/library paths and rejects host package leakage. Parent
actual-library tests verified runtime loader paths/hashes, full quick/release,
25 audio TSan cases and 8192-frame bit-exact native/Ogg FLAC round-trips. These
tests used an independent source copy, not candidate adoption. See
[build instructions](vendor-rebuilds.md) and [build proof](../publication/vendor-build-proof.json).

## GRDB.swift

The clean checkout, v6.29.3 tag and authenticated
[remote tag](https://api.github.com/repos/groue/GRDB.swift/git/ref/tags/v6.29.3)
identify revision 2cf6c756e1e5ef6901ebae16576a7e4e4b834622. The source review checked
848 tracked blobs and found no mismatch. This is not a standalone dynamic library:
the component record uses linkage static and an empty binary_files list.

The owner approved production-source vendoring with a documented minimal upstream
manifest adaptation removing the upstream test target/resources. In particular,
Betty.jpeg has no independently established asset grant in the reviewed evidence
and is not imported. Preserve production source, CSQLite module map/shim,
PrivacyInfo.xcprivacy and all applicable notices; omit the unrelated custom SQLite
gitlink/submodule. Keep Songbird's own tests and ordinary Package.resolved unchanged.
Unset SPI_BUILDER and explicitly control SQLITE_ENABLE_PREUPDATE_HOOK when proving
the offline build. The approved import is now integrated: 169 upstream files
(168 unchanged and one adapted manifest) plus two supplemental notices. The parent
reverified all 169 upstream Git blobs before importing, then built a frozen current
source copy normally offline and under OS-enforced network denial. Both compiled
all 164 production Swift files and the identical privacy resource with empty
dependency checkout/repository directories. See [the import record](grdb-source-import.md)
and [parent build proof](../publication/grdb-offline-build-proof.json). Actual executable
hash receipts remain external. SwiftPM's removal of the unused remote lockfile was
contained/restored only in the disposable build copy, not the candidate.

Root GRDB MIT is not the complete notice scope: Inflections+English.swift retains
Gwendal Roué and Rails-derived David Heinemeier Hansson MIT notices. Cursor.swift,
EncodableRecord.swift and FetchableRecord.swift retain Apple/Swift-derived
Apache-2.0-with-Runtime-Library-Exception notices. Those source attributions and the
full [Swift license](https://www.swift.org/LICENSE.txt), SHA-256
167beb36f181bd163c93c6feb45c68e5f9462fe1af55b278f7bfd1df20e673a3,
are now included in the canonical third-party text. The compiler-embedding exception
is preserved, not used to silently waive adapted-source attribution obligations.

## Remaining acceptance

The source imports and controlled outputs are prepared and tested. The S7 approval
prompt received no answer; no candidate runtime binary was replaced. Until final
source/archive acceptance and explicit S7 adoption are complete, component
status stays blocked. A matching row/hash does not grant trademark, service-content,
privacy or distribution rights. No public release URL, signed package or initial
commit has been created.
