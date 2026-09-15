"""Exercise actual SwiftPM manifest evaluation without resolving/fetching packages."""
import difflib
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


def dump_manifest(root, offline):
    with tempfile.TemporaryDirectory(prefix="songbird-grdb-manifest-") as temporary:
        home = Path(temporary) / "home"
        home.mkdir()
        env = os.environ.copy()
        for name in ("SPI_BUILDER", "SQLITE_ENABLE_PREUPDATE_HOOK", "SONGBIRD_OFFLINE_DEPS",
                     "SONGBIRD_STORE_FIXTURE", "SONGBIRD_V1_STORE_FIXTURE"):
            env.pop(name, None)
        env.update(HOME=str(home), CFFIXED_USER_HOME=str(home), SONGBIRD_UI_TESTING="1",
                   SONGBIRD_UI_TEST_ROOT=str(Path(temporary) / "test-root"))
        if offline is not None:
            env["SONGBIRD_OFFLINE_DEPS"] = offline
        # Only evaluate a private manifest copy. dump-package does not resolve paths.
        package = Path(temporary) / "package"
        package.mkdir()
        shutil.copyfile(root / "Package.swift", package / "Package.swift")
        result = subprocess.run(["swift", "package", "--package-path", str(package),
                                 "dump-package"], env=env, capture_output=True, text=True)
        if result.returncode:
            raise AssertionError(result.stderr)
        # #filePath contributes absolute fixture paths to packageKind and linker flags.
        return json.loads(result.stdout.replace(str(package), "<manifest-fixture>"))


class GRDBOfflineTests(unittest.TestCase):
    def test_exact_opt_in_selects_local_grdb(self):
        package = dump_manifest(ROOT, "1")
        self.assertEqual(len(package["dependencies"]), 1)
        dependency = package["dependencies"][0]
        self.assertIn("fileSystem", dependency, "offline opt-in must not select remote GRDB")
        local = dependency["fileSystem"][0]
        self.assertEqual(local["identity"], "grdb.swift")
        self.assertTrue(local["path"].endswith("/Vendor/GRDB.swift"))
        self.assertIn("SongbirdTests", [target["name"] for target in package["targets"]])

    def test_non_opt_in_values_keep_original_remote_dependency(self):
        for value in (None, "", "0", "true", "01"):
            with self.subTest(value=value):
                package = dump_manifest(ROOT, value)
                self.assertEqual(len(package["dependencies"]), 1)
                remote = package["dependencies"][0]["sourceControl"][0]
                self.assertEqual(remote["identity"], "grdb.swift")
                self.assertEqual(remote["location"]["remote"][0]["urlString"],
                                 "https://github.com/groue/GRDB.swift.git")
                self.assertEqual(remote["requirement"]["range"],
                                 [{"lowerBound": "6.24.0", "upperBound": "7.0.0"}])

    def test_offline_selection_preserves_every_songbird_target(self):
        normal = dump_manifest(ROOT, None)
        offline = dump_manifest(ROOT, "1")
        normal.pop("dependencies")
        offline.pop("dependencies")
        # SwiftPM embeds each disposable evaluation directory in packageKind.
        normal.pop("packageKind")
        offline.pop("packageKind")
        self.assertEqual(normal, offline)

    def test_manifest_delta_only_removes_upstream_test_target(self):
        original = (ROOT / "publication/grdb-upstream-Package.swift").read_bytes()
        start = original.index(b"        .testTarget(\n")
        end = original.index(b"    ],\n    swiftLanguageVersions:", start)
        expected = original[:start] + original[end:]
        self.assertEqual((ROOT / "Vendor/GRDB.swift/Package.swift").read_bytes(), expected)

    def test_vendored_manifest_has_only_production_targets(self):
        vendor = ROOT / "Vendor/GRDB.swift"
        self.assertTrue((vendor / "Package.swift").is_file(), "vendored manifest must be supplied")
        package = dump_manifest(vendor, "1")
        self.assertEqual([target["name"] for target in package["targets"]], ["CSQLite", "GRDB"])
        self.assertEqual(package["dependencies"], [])
        grdb = package["targets"][1]
        self.assertEqual(grdb["path"], "GRDB")
        self.assertEqual(grdb["resources"], [{"path": "PrivacyInfo.xcprivacy", "rule": {"copy": {}}}])

    def test_every_imported_file_matches_inventory(self):
        inventory = json.loads((ROOT / "publication/grdb-source-inventory.json").read_text())
        self.assertEqual(inventory["revision"], "2cf6c756e1e5ef6901ebae16576a7e4e4b834622")
        self.assertEqual(inventory["upstream_tag"], "v6.29.3")
        imported = inventory["imported_files"]
        self.assertEqual(len(imported), 169)
        self.assertEqual(sum(row["modified"] for row in imported), 1)
        rows = imported + inventory["supplemental_notices"]
        self.assertEqual(len(rows), len({row["path"] for row in rows}))
        actual = {path.relative_to(ROOT).as_posix()
                  for path in (ROOT / "Vendor/GRDB.swift").rglob("*") if path.is_file()}
        self.assertEqual(actual, {row["path"] for row in rows})
        for row in rows:
            with self.subTest(path=row["path"]):
                path = ROOT / row["path"]
                self.assertFalse(path.is_symlink())
                self.assertEqual(path.stat().st_nlink, 1)
                data = path.read_bytes()
                self.assertEqual(hashlib.sha256(data).hexdigest(), row["sha256"])
                self.assertEqual(len(data), row["bytes"])
                self.assertEqual(format(path.stat().st_mode & 0o777, "04o"), row["mode"])
                if "upstream_sha256" in row and not row["modified"]:
                    self.assertEqual(row["sha256"], row["upstream_sha256"])
        self.assertEqual(sum(row["path"].endswith(".swift") and "/GRDB/" in row["path"]
                             for row in imported), 164)

    def test_manifest_patch_and_original_are_exact(self):
        original = (ROOT / "publication/grdb-upstream-Package.swift").read_bytes()
        inventory = json.loads((ROOT / "publication/grdb-source-inventory.json").read_text())
        row = next(row for row in inventory["imported_files"] if row["upstream_path"] == "Package.swift")
        self.assertEqual(hashlib.sha256(original).hexdigest(), row["upstream_sha256"])
        adapted = (ROOT / row["path"]).read_text()
        expected = "".join(difflib.unified_diff(original.decode().splitlines(keepends=True),
                           adapted.splitlines(keepends=True), fromfile="a/Package.swift", tofile="b/Package.swift"))
        self.assertEqual((ROOT / "publication/grdb-manifest.patch").read_text(), expected)

    def test_nested_notices_are_delivered_verbatim(self):
        vendor = ROOT / "Vendor/GRDB.swift"
        inflections = (vendor / "GRDB/Utils/Inflections+English.swift").read_bytes()
        self.assertEqual((vendor / "Notices/Inflections-MIT.txt").read_bytes(),
                         b"".join(inflections.splitlines(keepends=True)[:43]))
        swift_license = vendor / "Notices/Swift-Apache-2.0-with-Runtime-Exception.txt"
        self.assertEqual(hashlib.sha256(swift_license.read_bytes()).hexdigest(),
                         "167beb36f181bd163c93c6feb45c68e5f9462fe1af55b278f7bfd1df20e673a3")
        self.assertEqual(hashlib.sha256((vendor / "LICENSE").read_bytes()).hexdigest(),
                         "b9ce5b40c859a62fa6998995a9d284565aba72e92ca7c655f64777948f885139")

    def test_omissions_are_disjoint_complete_and_not_copied(self):
        inventory = json.loads((ROOT / "publication/grdb-source-inventory.json").read_text())
        imported = {row["upstream_path"] for row in inventory["imported_files"]}
        omitted_rows = inventory["omitted_upstream_entries"]
        omitted = {row["path"] for row in omitted_rows}
        self.assertEqual(len(omitted), 680)  # 679 Git blobs + one separate Git submodule
        self.assertEqual(len(omitted), len(omitted_rows))
        self.assertFalse(imported & omitted)
        for row in omitted_rows:
            self.assertTrue(row["omission_reason"])
            self.assertFalse((ROOT / "Vendor/GRDB.swift" / row["path"]).exists())
        self.assertIn("Tests/GRDBTests/Betty.jpeg", omitted)
        self.assertIn("SQLiteCustom/src", omitted)
        self.assertFalse((ROOT / "Vendor/GRDB.swift/.git").exists())
        self.assertFalse((ROOT / "Vendor/GRDB.swift/Tests").exists())


if __name__ == "__main__":
    unittest.main()
