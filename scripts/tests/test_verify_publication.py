"""Real Git commands operate exclusively on disposable synthetic repositories."""
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from publication_checks import file_record

SCRIPT = Path(__file__).resolve().parents[1] / "verify-publication.py"
MANIFEST = "publication/manifest.json"
RETIRED = "publication/retired-asset-hashes.json"


class VerifyPublicationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="publication-git-")
        self.addCleanup(self.temp.cleanup)
        self.sandbox = Path(self.temp.name).resolve()
        self.root = self.sandbox / "repo"
        self.root.mkdir()
        home = self.sandbox / "home"
        home.mkdir()
        self.env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
        self.env.update(HOME=str(home), XDG_CONFIG_HOME=str(home),
                        GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull,
                        GIT_TERMINAL_PROMPT="0", PYTHONDONTWRITEBYTECODE="1")
        self.git("init", "--initial-branch=main", "--template=")
        self.git("config", "core.autocrlf", "false")
        self.git("config", "core.filemode", "true")
        self.write("source.txt", b"synthetic source")
        self.write(RETIRED, json.dumps({"schema": 1, "sha256": []}).encode())
        self.write(".gitignore", b".build/\n.env*\n*.app/\nmuseeks-*/\n__pycache__/\n")
        self.paths = ["source.txt", RETIRED, ".gitignore"]
        self.seal()

    def write(self, name, data):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        path.chmod(0o644)

    def git(self, *args, input=None):
        result = subprocess.run(["git", "--no-optional-locks", "-C", str(self.root), *args],
                                env=self.env, input=input, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        return result.stdout

    def seal(self):
        # This is only a synthetic fixture manifest, not a production sealer.
        rows = [dict(file_record(self.root, p), origin="synthetic-fixture") for p in self.paths]
        self.write(MANIFEST, json.dumps({"schema": 1, "self_path": MANIFEST,
                   "payload_file_count_including_manifest": len(rows) + 1, "files": rows}).encode())

    def invoke(self, phase="development", *args, env=None):
        return subprocess.run([sys.executable, str(SCRIPT), phase, str(self.root), *map(str, args)],
                              env=env or self.env, capture_output=True, text=True, timeout=10)

    def succeeds(self, phase="development", *args):
        result = self.invoke(phase, *args)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "Publication payload verified: " + phase)

    def fails(self, phase="development", *args, message=None, env=None):
        result = self.invoke(phase, *args, env=env)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertNotIn("Publication payload verified:", result.stdout)
        if message:
            self.assertIn(message, result.stderr)
        return result

    def commit(self):
        self.git("add", "--", *self.paths, MANIFEST)
        self.git("-c", "user.name=Synthetic Fixture", "-c", "user.email=fixture@example.invalid",
                 "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null",
                 "commit", "--no-verify", "-m", "synthetic fixture only")

    def test_development_rejects_unlisted_untracked_and_removed_still_present(self):
        self.write("unlisted.txt", b"extra")
        self.fails(message="files differ")
        (self.root / "unlisted.txt").unlink()
        self.paths.remove("source.txt")
        self.seal()
        self.fails(message="files differ")

    def test_development_includes_tracked_files_even_when_ignored(self):
        self.commit()
        self.write(".gitignore", b"source.txt\n")
        self.paths.remove("source.txt")
        self.seal()
        self.fails(message="files differ")

    def test_real_git_failure_never_means_empty_inventory(self):
        (self.root / ".git/index").write_bytes(b"synthetic corrupt index")
        self.fails(message="Git command failed")

    def test_pre_seed_requires_unborn_main(self):
        self.succeeds("pre-seed")
        self.commit()
        self.fails("pre-seed", message="Initial commit")
        self.succeeds("development")

    def test_pre_seed_rejects_other_branch(self):
        self.git("symbolic-ref", "HEAD", "refs/heads/other")
        self.fails("pre-seed", message="unborn main")

    def test_pre_seed_rejects_index(self):
        self.git("add", "--", "source.txt")
        self.fails("pre-seed", message="refs/remotes/index")

    def test_pre_seed_rejects_remote(self):
        self.git("remote", "add", "synthetic", "https://example.invalid/never-accessed")
        self.fails("pre-seed", message="refs/remotes/index")

    def test_pre_seed_rejects_loose_objects(self):
        self.git("hash-object", "-w", "--stdin", input=b"synthetic unreferenced object")
        self.fails("pre-seed", message="contains objects")

    def test_pre_seed_rejects_refs_while_main_is_unborn(self):
        oid = self.git("hash-object", "-w", "--stdin", input=b"synthetic tag target").strip().decode()
        self.git("update-ref", "refs/tags/synthetic", oid)
        self.fails("pre-seed", message="refs/remotes/index")

    def test_external_git_routing_is_rejected_before_commands(self):
        for key, value in (("GIT_DIR", str(self.root / ".git")),
                           ("GIT_WORK_TREE", str(self.root)),
                           ("GIT_COMMON_DIR", str(self.root / ".git")),
                           ("GIT_INDEX_FILE", str(self.sandbox / "alternate-index")),
                           ("GIT_OBJECT_DIRECTORY", str(self.root / ".git/objects")),
                           ("GIT_ALTERNATE_OBJECT_DIRECTORIES", str(self.root / ".git/objects"))):
            with self.subTest(key=key):
                self.fails(message="Git routing", env=dict(self.env, **{key: value}))

    def test_repository_must_own_git_directory(self):
        saved = self.sandbox / "saved-git"
        (self.root / ".git").rename(saved)
        (self.root / ".git").symlink_to(saved, target_is_directory=True)
        self.fails(message="own its Git directory")
        (self.root / ".git").unlink()
        (self.root / ".git").write_text("gitdir: " + str(saved) + "\n")
        self.fails(message="own its Git directory")

    def test_dangling_alternate_link_is_rejected_without_following(self):
        (self.root / ".git/objects/info/alternates").symlink_to(self.sandbox / "missing")
        self.fails(message="Git linkage")

    def test_index_checks_actual_staged_blob_not_restored_worktree(self):
        original = (self.root / "source.txt").read_bytes()
        self.git("add", "--", *self.paths, MANIFEST)
        self.succeeds("index")
        self.write("source.txt", b"wrong staged bytes")
        self.git("add", "--", "source.txt")
        self.write("source.txt", original)
        self.fails("index", message="Staged blob/mode mismatch")
        self.succeeds("development")

    def test_index_requires_complete_staging(self):
        self.fails("index", message="incomplete")
        self.git("add", "--", *self.paths, MANIFEST)
        self.git("rm", "--cached", "--", "source.txt")
        self.fails("index", message="incomplete")

    def test_index_binds_executable_mode(self):
        self.git("add", "--", *self.paths, MANIFEST)
        self.git("update-index", "--chmod=+x", "source.txt")
        self.fails("index", message="Staged blob/mode mismatch")

    def test_index_binds_manifest_blob_independently(self):
        self.git("add", "--", *self.paths, MANIFEST)
        value = json.loads((self.root / MANIFEST).read_text())
        value["synthetic_note"] = "different intended manifest"
        self.write(MANIFEST, json.dumps(value).encode())
        self.fails("index", message="Staged blob/mode mismatch: " + MANIFEST)

    def test_index_rejects_conflicted_stages(self):
        self.git("add", "--", *self.paths, MANIFEST)
        oid = self.git("hash-object", "--", "source.txt").strip()
        self.git("update-index", "--force-remove", "--", "source.txt")
        self.git("update-index", "--index-info", input=b"100644 " + oid + b" 1\tsource.txt\n")
        self.fails("index", message="conflicted index")

    def archive(self, mutate=None):
        path = self.sandbox / "synthetic.tar"
        entries = []
        for name in self.paths + [MANIFEST]:
            row = file_record(self.root, name)
            entries.append((name, (self.root / name).read_bytes(), row["mode"], tarfile.REGTYPE))
        if mutate:
            entries = mutate(entries)
        with tarfile.open(path, "w") as handle:
            for name, data, mode, kind in entries:
                member = tarfile.TarInfo(name)
                member.size, member.mode, member.type = len(data), mode, kind
                if kind != tarfile.REGTYPE:
                    member.size = 0
                    member.linkname = "source.txt"
                    handle.addfile(member)
                else:
                    handle.addfile(member, io.BytesIO(data))
        return path

    def test_archive_cli_requires_exact_payload_and_manifest(self):
        self.succeeds("archive", self.archive())
        self.fails("archive", self.archive(lambda rows: rows[:-1]), message="Incomplete archive")
        self.fails("archive", self.archive(lambda rows: rows + [rows[0]]), message="Unexpected archive")
        self.fails("archive", message="Archive path required")

    def test_archive_cli_binds_bytes_modes_and_rejects_links(self):
        for field, value in ((0, "../source.txt"), (1, b"different"),
                             (2, 0o755), (3, tarfile.LNKTYPE), (3, tarfile.SYMTYPE)):
            with self.subTest(field=field, value=value):
                def mutation(rows):
                    row = list(rows[0])
                    row[field] = value
                    return [tuple(row)] + rows[1:]
                self.fails("archive", self.archive(mutation))

    def test_manifest_schema_counts_and_self_hash_exception_are_explicit(self):
        original = json.loads((self.root / MANIFEST).read_text())
        for field, value in (("schema", 2), ("self_path", "other.json"),
                             ("payload_file_count_including_manifest", 999),
                             ("files", original["files"] + [original["files"][0]]),
                             ("files", original["files"] + [file_record(self.root, MANIFEST)])):
            with self.subTest(field=field):
                self.write(MANIFEST, json.dumps(dict(original, **{field: value})).encode())
                self.fails()
        self.write(MANIFEST, json.dumps(original).encode())

    def test_retired_hash_is_rejected_under_an_innocent_new_name(self):
        digest = file_record(self.root, "source.txt")["sha256"]
        self.write(RETIRED, json.dumps({"schema": 1, "sha256": [digest]}).encode())
        self.seal()
        self.fails(message="Retired artwork")

    def test_excluded_paths_never_become_payload_even_when_explicitly_listed(self):
        for name in (".env", "keys/signing.p12", ".build/output", "Nested/App.app/file",
                     "museeks-synthetic/file", "nightingale-media-player-synthetic/file",
                     "Resources/reference", "Usability/reports/run.json", "nested/.git/config"):
            with self.subTest(name=name):
                self.write(name, b"synthetic excluded fixture")
                self.paths.append(name)
                self.seal()
                self.fails(message="Excluded payload path")
                self.paths.pop()
                (self.root / name).unlink()
        self.seal()

    def test_excluded_untracked_subtrees_are_pruned_without_ignore_rules(self):
        self.write(".gitignore", b"")
        for name in (".build/never-descend", "museeks-synthetic/never-descend", "Usability/reports/never-descend"):
            self.write(name, b"synthetic excluded fixture")
        self.seal()
        self.succeeds()

    def test_manifest_duplicate_json_keys_are_rejected(self):
        raw = (self.root / MANIFEST).read_text().replace('"schema": 1', '"schema": 2, "schema": 1')
        self.write(MANIFEST, raw.encode())
        self.fails(message="Duplicate JSON")

    def test_retired_denylist_schema_is_validated(self):
        for value in ({"schema": 2, "sha256": []}, {"schema": 1, "sha256": ""},
                      {"schema": 1, "sha256": ["not-a-hash"]}):
            with self.subTest(value=value):
                self.write(RETIRED, json.dumps(value).encode())
                self.seal()
                self.fails(message="Retired asset schema")

    def test_index_cannot_substitute_replacement_object_for_actual_blob(self):
        original = (self.root / "source.txt").read_bytes()
        self.git("add", "--", *self.paths, MANIFEST)
        good = self.git("hash-object", "--", "source.txt").strip().decode()
        self.write("source.txt", b"wrong staged source")
        self.git("add", "--", "source.txt")
        bad = self.git("hash-object", "--", "source.txt").strip().decode()
        self.write("source.txt", original)
        self.git("replace", bad, good)
        self.fails("index", message="Staged blob/mode mismatch")

    def test_pre_seed_rejects_broken_refs_instead_of_calling_them_unborn(self):
        (self.root / ".git/refs/heads/main").write_text("1" * 40 + "\n")
        self.fails("pre-seed", message="refs/remotes/index")

    def test_linked_git_object_directory_is_rejected(self):
        objects = self.root / ".git/objects"
        saved = self.sandbox / "saved-objects"
        objects.rename(saved)
        objects.symlink_to(saved, target_is_directory=True)
        self.fails(message="Symlink")

    def test_missing_worktree_file_is_rejected(self):
        self.commit()
        (self.root / "source.txt").unlink()
        self.fails(message="Missing regular file")

    def test_worktree_permission_mutation_is_rejected(self):
        (self.root / "source.txt").chmod(0o755)
        self.fails(message="Record mismatch")

    def test_unlisted_index_path_cannot_hide_by_worktree_deletion(self):
        self.git("add", "--", *self.paths, MANIFEST)
        self.write("extra.txt", b"synthetic extra index blob")
        self.git("add", "--", "extra.txt")
        (self.root / "extra.txt").unlink()
        self.fails("index", message="files differ")

    def test_missing_staged_object_reports_real_git_failure(self):
        self.git("add", "--", *self.paths, MANIFEST)
        self.git("update-index", "--add", "--cacheinfo", "100644," + "1" * 40 + ",source.txt")
        self.fails("index", message="Git command failed: cat-file blob")

    def test_special_index_mode_is_rejected_even_with_matching_blob(self):
        self.git("add", "--", *self.paths, MANIFEST)
        oid = self.git("hash-object", "--", "source.txt").strip().decode()
        self.git("update-index", "--add", "--cacheinfo", "120000," + oid + ",source.txt")
        self.fails("index", message="Staged blob/mode mismatch")

    def test_pre_seed_rejects_packed_unreferenced_objects(self):
        oid = self.git("hash-object", "-w", "--stdin", input=b"synthetic packed object").strip()
        self.git("pack-objects", str(self.root / ".git/objects/pack/synthetic"), input=oid + b"\n")
        digest = oid.decode()
        (self.root / ".git/objects" / digest[:2] / digest[2:]).unlink()
        self.fails("pre-seed", message="contains objects")

    def test_manifest_parent_symlink_rejected(self):
        original = self.root / "publication"
        saved = self.sandbox / "saved-publication"
        original.rename(saved)
        original.symlink_to(saved, target_is_directory=True)
        self.fails(message="Symlink")

    def test_archive_argument_cannot_be_silently_ignored_by_other_phases(self):
        for phase in ("development", "pre-seed", "index"):
            with self.subTest(phase=phase):
                self.fails(phase, self.sandbox / "unused.tar", message="Archive argument only valid")

    def test_development_verifies_current_bytes_before_and_after_first_commit(self):
        self.succeeds()
        self.commit()
        self.succeeds()
        self.write("source.txt", b"changed source")
        self.fails(message="Record mismatch")
