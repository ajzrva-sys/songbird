"""Synthetic-only publication integrity fixtures; never inspect user data."""
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import publication_checks as checks


def fixture_tar(entries):
    output = io.BytesIO()
    with tarfile.open(fileobj=output, mode="w") as archive:
        for name, data, kind, mode in entries:
            info = tarfile.TarInfo(name)
            info.type, info.mode = kind, mode
            if kind == tarfile.REGTYPE:
                info.size = len(data)
                archive.addfile(info, io.BytesIO(data))
            else:
                info.linkname = "source.txt"
                archive.addfile(info)
    output.seek(0)
    return output


class PublicationChecksTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="publication-unit-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.path = self.root / "source.txt"
        self.data = b"synthetic source fixture"
        self.path.write_bytes(self.data)
        self.path.chmod(0o644)
        self.row = {"path": "source.txt", "sha256": hashlib.sha256(self.data).hexdigest(),
                    "bytes": len(self.data), "mode": 0o644}

    def test_paths_are_exact_canonical_relative_names(self):
        self.assertEqual(checks.relative("dir/file with space"),
                         PurePosixPath("dir/file with space"))
        for name in ("", ".", "..", "../source", "/source", "a/../b", "a//b",
                     "./source", "a/./b", "a/", "a\\b", "a\x00b", None, 12):
            with self.subTest(name=name), self.assertRaises(ValueError):
                checks.relative(name)

    def test_file_record_rejects_links_without_following_them(self):
        for kind in ("symlink", "parent-symlink", "hardlink"):
            with self.subTest(kind=kind):
                link = self.root / kind
                if kind == "parent-symlink":
                    link.symlink_to(self.root, target_is_directory=True)
                    name = kind + "/source.txt"
                elif kind == "hardlink":
                    os.link(self.path, link)
                    name = kind
                else:
                    link.symlink_to(self.path)
                    name = kind
                with self.assertRaisesRegex(ValueError, "[Ll]ink"):
                    checks.file_record(self.root, name)
                link.unlink()

    def test_file_record_rejects_nonregular_and_missing_inputs(self):
        (self.root / "directory").mkdir()
        for name in ("missing", "directory"):
            with self.subTest(name=name):
                try:
                    with self.assertRaisesRegex(ValueError, "regular"):
                        checks.file_record(self.root, name)
                except OSError as error:
                    self.fail(f"Missing regular-file validation: {error}")

    def test_verify_rows_rejects_exact_record_mismatches(self):
        checks.verify_rows(self.root, [self.row])
        for change in ({"sha256": "0" * 64}, {"bytes": 2}, {"mode": 0o755},
                       {"unexpected": "metadata"}):
            with self.subTest(change=change), self.assertRaises(ValueError):
                checks.verify_rows(self.root, [dict(self.row, **change)])
        with self.assertRaisesRegex(ValueError, "Duplicate"):
            checks.verify_rows(self.root, [self.row, self.row])

    def test_indexed_rejects_malformed_record_schema(self):
        for change in ({"sha256": "g" * 64}, {"sha256": "A" * 64},
                       {"sha256": None}, {"bytes": -1}, {"bytes": True},
                       {"mode": False}, {"mode": 0o100644}, {"extra": 1}):
            with self.subTest(change=change), self.assertRaises(ValueError):
                checks.indexed([dict(self.row, **change)])
        for rows in ({}, None, [None], [{"path": "source.txt"}]):
            with self.subTest(rows=rows):
                try:
                    with self.assertRaises(ValueError):
                        checks.indexed(rows)
                except (TypeError, KeyError) as error:
                    self.fail(f"Missing schema validation: {error}")

    def test_archive_is_exact_canonical_file_only_membership(self):
        good = ("source.txt", self.data, tarfile.REGTYPE, 0o644)
        checks.verify_archive(fixture_tar([good]), [self.row])
        cases = [[], [good, good], [good, ("extra", b"x", tarfile.REGTYPE, 0o644)]]
        cases += [[(name, self.data, tarfile.REGTYPE, 0o644)] for name in
                  ("../source.txt", "/source.txt", "./source.txt", "a//source.txt")]
        cases += [[("source.txt", b"", kind, 0o644)] for kind in
                  (tarfile.SYMTYPE, tarfile.LNKTYPE, tarfile.DIRTYPE,
                   tarfile.FIFOTYPE, tarfile.CHRTYPE, tarfile.BLKTYPE)]
        for entries in cases:
            with self.subTest(entries=entries), self.assertRaises(ValueError):
                checks.verify_archive(fixture_tar(entries), [self.row])
        self.assertEqual({p.name for p in self.root.iterdir()}, {"source.txt"})

    def test_archive_binds_exact_content_length_and_mode(self):
        for data, mode in ((b"changed", 0o644), (b"x" * len(self.data), 0o644),
                           (self.data, 0o755)):
            with self.subTest(data=data, mode=mode), self.assertRaises(ValueError):
                checks.verify_archive(fixture_tar([
                    ("source.txt", data, tarfile.REGTYPE, mode)]), [self.row])

    def test_unreadable_archive_member_is_rejected_explicitly(self):
        archive = fixture_tar([('source.txt', self.data, tarfile.REGTYPE, 0o644)])
        with patch.object(tarfile.TarFile, 'extractfile', return_value=None):
            try:
                with self.assertRaisesRegex(ValueError, 'Unreadable archive member'):
                    checks.verify_archive(archive, [self.row])
            except (TypeError, AttributeError) as error:
                self.fail('Missing unreadable-member validation: ' + str(error))

    def test_snapshot_digest_is_order_independent_and_record_bound(self):
        other = dict(self.row, path="other.txt")
        expected = hashlib.sha256(json.dumps([other, self.row], sort_keys=True,
                    separators=(",", ":")).encode()).hexdigest()
        self.assertEqual(checks.snapshot_digest([self.row, other]), expected)
        self.assertEqual(checks.snapshot_digest([other, self.row]), expected)
        self.assertNotEqual(checks.snapshot_digest([dict(other, mode=0o755), self.row]), expected)
        with self.assertRaises(ValueError):
            checks.snapshot_digest([self.row, self.row])

    def component(self):
        source = self.root / "Vendor/synthetic"
        source.mkdir(parents=True)
        (source / "code.txt").write_bytes(self.data)
        (source / "code.txt").chmod(0o644)
        rows = [checks.file_record(self.root, "Vendor/synthetic/code.txt")]
        return {"id": "synthetic", "status": "verified", "source_root": "Vendor/synthetic",
                "source_files": rows, "snapshot_sha256": checks.snapshot_digest(rows),
                "build_files": [self.row], "binary_files": [self.row],
                "evidence_files": [self.row]}

    def test_component_inventory_rejects_extra_missing_and_changed_source(self):
        component = self.component()
        checks.verify_component(self.root, component)
        source = self.root / "Vendor/synthetic/code.txt"
        for mutation in ("extra", "missing", "changed", "mode"):
            with self.subTest(mutation=mutation):
                extra = source.parent / "extra.txt"
                if mutation == "extra":
                    extra.write_bytes(b"extra")
                elif mutation == "missing":
                    source.unlink()
                elif mutation == "changed":
                    source.write_bytes(b"altered")
                else:
                    source.chmod(0o755)
                with self.assertRaises(ValueError):
                    checks.verify_component(self.root, component)
                if extra.exists():
                    extra.unlink()
                source.write_bytes(self.data)
                source.chmod(0o644)

    def test_component_requires_verified_snapshot_and_evidence(self):
        component = self.component()
        for field, value in (("status", "blocked"), ("snapshot_sha256", "0" * 64),
                             ("build_files", []), ("binary_files", []),
                             ("evidence_files", []), ("evidence_files", [dict(self.row, sha256="0" * 64)])):
            with self.subTest(field=field), self.assertRaises(ValueError):
                checks.verify_component(self.root, dict(component, **{field: value}))
        checks.verify_component(self.root, dict(component, id="grdb.swift",
                                linkage="static", binary_files=[]))
        with self.assertRaises(ValueError):
            checks.verify_component(self.root, dict(component, id="aubio",
                                    linkage="static", binary_files=[]))

    def test_component_rejects_directory_links_even_when_not_in_inventory(self):
        component = self.component()
        (self.root / "Vendor/synthetic/unlisted-link").symlink_to(self.root, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "[Ss]ymlink"):
            checks.verify_component(self.root, component)

    def test_component_source_root_checks_ancestors_before_enumeration(self):
        component = self.component()
        real = self.root / "Vendor"
        saved = self.root / "saved-vendor"
        real.rename(saved)
        real.symlink_to(saved, target_is_directory=True)
        # Empty rows force an inventory error if enumeration occurs first.
        component["source_files"] = []
        with self.assertRaisesRegex(ValueError, "Symlink"):
            checks.verify_component(self.root, component)

    def test_component_does_not_scan_excluded_source_or_evidence(self):
        component = self.component()
        for name in (".env", "museeks-synthetic", "Vendor/synthetic/.git"):
            with self.subTest(name=name):
                with self.assertRaisesRegex(ValueError, "Excluded payload path"):
                    checks.verify_component(self.root, dict(component, source_root=name))
        component["evidence_files"] = [dict(self.row, path=".env")]
        with self.assertRaisesRegex(ValueError, "Excluded payload path"):
            checks.verify_component(self.root, component)

    def test_component_rejects_excluded_directory_before_descending(self):
        component = self.component()
        hidden = self.root / "Vendor/synthetic/.git"
        hidden.mkdir()
        (hidden / "never-follow").symlink_to(self.root, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "Excluded payload path"):
            checks.verify_component(self.root, component)

    def test_file_record_binds_bytes_length_and_permissions(self):
        self.assertEqual(checks.file_record(self.root, "source.txt"), self.row)
