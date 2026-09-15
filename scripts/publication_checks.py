"""Integrity primitives for explicitly selected publication inputs."""

from pathlib import Path, PurePosixPath
import hashlib
import stat
import re
import os
import fnmatch
import json
import tarfile


BANNED_ROOTS = {
    ".hermes", ".cursor", ".mimocode", ".build", ".swiftpm", "DerivedData",
    "Resources", "songbird-images", "carousel", "Cog-main", "Swinsian.app",
    "Nightingale.app", "Nightingale",
}
BANNED_PARTS = (".git", "__pycache__", ".DS_Store", "*.app", ".env", ".env.*",
                "*.p12", "*.pfx", "*.pyc", "*.o", "*.dSYM", "*.xcuserdata")
EXCLUDE_PATTERNS = (tuple("/" + name + "/" for name in sorted(BANNED_ROOTS))
                    + ("/museeks-*/", "/nightingale-media-player-*/", "/Usability/reports/")
                    + BANNED_PARTS)


def safe_payload_name(name):
    path = relative(name)
    if (path.parts[0] in BANNED_ROOTS
            or path.parts[0].startswith(("museeks-", "nightingale-media-player-"))
            or any(fnmatch.fnmatchcase(part, pattern) for part in path.parts for pattern in BANNED_PARTS)
            or path.parts[:2] == ("Usability", "reports")):
        raise ValueError("Excluded payload path: " + name)
    return path


def load_json(root, name):
    # Check links and regular-file identity before parsing any control content.
    data, _ = read_regular(root, name)

    def unique_object(pairs):
        value = {}
        for key, item in pairs:
            if key in value:
                raise ValueError("Duplicate JSON key: " + key)
            value[key] = item
        return value

    value = json.loads(data.decode("utf-8"), object_pairs_hook=unique_object)
    if not isinstance(value, dict):
        raise ValueError("Expected JSON object: " + name)
    return value


def verify_archive(fileobj, rows):
    wanted = indexed(rows)
    seen = set()
    with tarfile.open(fileobj=fileobj, mode="r:*") as archive:
        for member in archive:
            name = member.name
            relative(name)
            if member.type not in (tarfile.REGTYPE, tarfile.AREGTYPE) or name in seen or name not in wanted:
                raise ValueError(f"Unexpected archive member: {name}")
            seen.add(name)
            row = wanted[name]
            if member.size != row["bytes"] or member.mode != row["mode"]:
                raise ValueError(f"Archive size/mode mismatch: {name}")
            stream = archive.extractfile(member)
            if stream is None:
                raise ValueError(f"Unreadable archive member: {name}")
            with stream:
                data = stream.read()
            if len(data) != row["bytes"] or hashlib.sha256(data).hexdigest() != row["sha256"]:
                raise ValueError(f"Archive content mismatch: {name}")
    if seen != set(wanted):
        raise ValueError("Incomplete archive")


def verify_component(root, component):
    if component["status"] != "verified":
        raise ValueError(f"Unverified component: {component['id']}")
    root = Path(root).absolute()
    source = root.joinpath(*safe_payload_name(component["source_root"]).parts)
    no_symlinks(source)
    if not source.is_dir():
        raise ValueError("Missing source tree")
    rows = component["source_files"]
    actual = set()
    pending = [source]
    while pending:
        directory = pending.pop()
        with os.scandir(directory) as entries:
            for entry in entries:
                path = Path(entry.path)
                name = path.relative_to(root).as_posix()
                safe_payload_name(name)
                if entry.is_symlink():
                    raise ValueError("Source symlink: " + name)
                if entry.is_dir(follow_symlinks=False):
                    pending.append(path)
                else:
                    actual.add(name)
    if not rows or actual != set(indexed(rows)):
        raise ValueError("Source inventory mismatch")
    if snapshot_digest(rows) != component["snapshot_sha256"]:
        raise ValueError("Source snapshot identity mismatch")
    verify_rows(root, rows)
    for field in ("build_files", "binary_files", "evidence_files"):
        records = component[field]
        static_grdb = (field == "binary_files" and component["id"] == "grdb.swift"
                       and component.get("linkage") == "static")
        if not records and not static_grdb:
            raise ValueError(f"Missing {field}")
        for name in indexed(records):
            safe_payload_name(name)
        verify_rows(root, records)


def snapshot_digest(rows):
    indexed(rows)
    data = json.dumps(sorted(rows, key=lambda row: row["path"]),
                      sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(data).hexdigest()


def indexed(rows):
    if not isinstance(rows, list):
        raise ValueError("Records must be a list")
    result = {}
    for row in rows:
        if not isinstance(row, dict) or set(row) != {"path", "sha256", "bytes", "mode"}:
            raise ValueError("Expected exact four-field file record")
        if (not isinstance(row["sha256"], str)
                or not re.fullmatch(r"[0-9a-f]{64}", row["sha256"])
                or type(row["bytes"]) is not int or row["bytes"] < 0
                or type(row["mode"]) is not int or not 0 <= row["mode"] <= 0o7777):
            raise ValueError("Invalid record hash/bytes/mode")
        name = row["path"]
        relative(name)
        if name in result:
            raise ValueError(f"Duplicate: {name}")
        result[name] = row
    return result


def verify_rows(root, rows):
    for name, row in indexed(rows).items():
        if file_record(root, name) != row:
            raise ValueError(f"Record mismatch: {name}")


def relative(name):
    if not isinstance(name, str) or not name or "\\" in name or "\x00" in name:
        raise ValueError("Invalid path")
    path = PurePosixPath(name)
    if path.is_absolute() or ".." in path.parts or path.as_posix() != name or name == ".":
        raise ValueError(f"Noncanonical path: {name!r}")
    return path


def no_symlinks(path):
    for parent in reversed((path, *path.parents)):
        if parent.is_symlink():
            raise ValueError(f"Symlink: {path}")


def read_regular(root, name):
    path = Path(root).absolute().joinpath(*relative(name).parts)
    no_symlinks(path)
    try:
        info = path.stat()
    except FileNotFoundError as error:
        raise ValueError(f"Missing regular file: {name}") from error
    if not stat.S_ISREG(info.st_mode):
        raise ValueError(f"Not regular: {name}")
    if info.st_nlink != 1:
        raise ValueError(f"Hardlink: {name}")
    return path.read_bytes(), info


def file_record(root, name):
    data, info = read_regular(root, name)
    return {"path": name, "sha256": hashlib.sha256(data).hexdigest(),
            "bytes": len(data), "mode": stat.S_IMODE(info.st_mode)}
