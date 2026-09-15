#!/usr/bin/env python3
"""Read-only phase verifier; never seals, stages, commits, or grants rights."""
import argparse
import hashlib
import re
import os
from pathlib import Path
import subprocess
from publication_checks import (EXCLUDE_PATTERNS, file_record, indexed, load_json, no_symlinks, relative,
                                safe_payload_name, verify_rows, verify_archive)

MANIFEST = "publication/manifest.json"
FIELDS = ("path", "sha256", "bytes", "mode")


def git(root, *args, allowed=(0,)):
    result = subprocess.run(["git", "--no-optional-locks", "--no-replace-objects", "-C", str(root), *args],
                            capture_output=True)
    if result.returncode not in allowed:
        raise ValueError("Git command failed: " + " ".join(args))
    return result


def eligible(root):
    exclusions = [arg for pattern in EXCLUDE_PATTERNS for arg in ("--exclude", pattern)]
    data = git(root, "ls-files", "--cached", "--others", "--exclude-standard", "-z", *exclusions).stdout
    names = set(filter(None, data.decode("utf-8").split("\0")))
    for name in names:
        safe_payload_name(name)
    return names


def manifest_rows(root):
    value = load_json(root, MANIFEST)
    if (type(value.get("schema")) is not int or value["schema"] != 1
            or value.get("self_path") != MANIFEST or not isinstance(value.get("files"), list)):
        raise ValueError("Payload manifest schema/self path mismatch")
    rows = [{field: row[field] for field in FIELDS} for row in value["files"]]
    if (type(value.get("payload_file_count_including_manifest")) is not int
            or value["payload_file_count_including_manifest"] != len(rows) + 1):
        raise ValueError("Payload manifest count mismatch")
    if MANIFEST in indexed(rows):
        raise ValueError("Self-referential manifest entry")
    for row in rows:
        safe_payload_name(row["path"])
    rows.append(file_record(root, MANIFEST))
    return rows


def reject_retired_assets(root, rows):
    value = load_json(root, "publication/retired-asset-hashes.json")
    if (type(value.get("schema")) is not int or value["schema"] != 1
            or not isinstance(value.get("sha256"), list)
            or any(not isinstance(item, str) or not re.fullmatch(r"[0-9a-f]{64}", item)
                   for item in value["sha256"])):
        raise ValueError("Retired asset schema mismatch")
    forbidden = set(value["sha256"])
    for row in rows:
        if row["sha256"] in forbidden:
            raise ValueError("Retired artwork still present: " + row["path"])


def no_external_git_linkage(root):
    for key in ("GIT_DIR", "GIT_WORK_TREE", "GIT_COMMON_DIR", "GIT_INDEX_FILE",
                "GIT_OBJECT_DIRECTORY", "GIT_ALTERNATE_OBJECT_DIRECTORIES"):
        if key in os.environ:
            raise ValueError("Unset external Git routing variable: " + key)
    directory = root / ".git"
    if directory.is_symlink() or not directory.is_dir():
        raise ValueError("Candidate must own its Git directory")
    for name in ("objects", "objects/info", "objects/pack", "refs", "refs/heads", "refs/tags"):
        no_symlinks(directory / name)
    for name in ("commondir", "gitdir", "objects/info/alternates"):
        path = directory / name
        if path.is_symlink() or path.exists():
            raise ValueError("Inherited Git linkage: " + name)


def pre_seed(root):
    if git(root, "symbolic-ref", "--short", "HEAD").stdout.strip() != b"main":
        raise ValueError("Expected unborn main")
    if git(root, "rev-parse", "--verify", "--quiet", "HEAD^{commit}", allowed=(0, 1)).returncode == 0:
        raise ValueError("Initial commit already exists")
    for args in (("for-each-ref", "--format=%(refname)"), ("remote",), ("ls-files", "-z")):
        if git(root, *args).stdout.strip():
            raise ValueError("Pre-seed refs/remotes/index must be empty")
    if any(path.is_symlink() or not path.is_dir() for path in (root / ".git/refs").rglob("*")):
        raise ValueError("Pre-seed refs/remotes/index must be empty")
    counts = dict(line.split(": ", 1) for line in
                  git(root, "count-objects", "-v").stdout.decode().splitlines() if ": " in line)
    if any(counts.get(key) != "0" for key in ("count", "in-pack", "packs", "garbage")):
        raise ValueError("Pre-seed repository contains objects")


def check_index(root, rows):
    wanted = indexed(rows)
    found = set()
    records = git(root, "ls-files", "--stage", "-z").stdout.split(b"\0")
    for record in filter(None, records):
        metadata, raw_name = record.split(b"\t", 1)
        mode, object_id, stage = metadata.decode("ascii").split()
        name = raw_name.decode("utf-8")
        relative(name)
        if stage != "0" or name in found or name not in wanted:
            raise ValueError("Unexpected/conflicted index entry: " + name)
        row = wanted[name]
        expected_mode = "100755" if row["mode"] & 0o111 else "100644"
        data = git(root, "cat-file", "blob", object_id).stdout
        if (mode != expected_mode or len(data) != row["bytes"]
                or hashlib.sha256(data).hexdigest() != row["sha256"]):
            raise ValueError("Staged blob/mode mismatch: " + name)
        found.add(name)
    if found != set(wanted):
        raise ValueError("Staged payload is incomplete")


def check(root, phase, archive=None):
    if phase != "archive" and archive is not None:
        raise ValueError("Archive argument only valid for archive phase")
    root = Path(root).absolute()
    no_external_git_linkage(root)
    rows = manifest_rows(root)
    if eligible(root) != set(indexed(rows)):
        raise ValueError("Git-eligible files differ from explicit payload")
    verify_rows(root, rows)
    reject_retired_assets(root, rows)
    if phase == "pre-seed":
        pre_seed(root)
    elif phase == "index":
        check_index(root, rows)
    elif phase == "archive":
        if archive is None:
            raise ValueError("Archive path required")
        with Path(archive).open("rb") as handle:
            verify_archive(handle, rows)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("phase", choices=("pre-seed", "index", "development", "archive"))
    parser.add_argument("root")
    parser.add_argument("archive", nargs="?")
    args = parser.parse_args()
    try:
        check(args.root, args.phase, args.archive)
    except (ValueError, OSError, KeyError, TypeError) as error:
        raise SystemExit(str(error))
    print("Publication payload verified: " + args.phase)
