"""All verified evidence below is explicitly synthetic, never an approval."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from publication_checks import file_record, snapshot_digest

SCRIPT = Path(__file__).resolve().parents[1] / "check-release-gates.py"
GATE_PATH = "publication/release-gates.json"
REQUIRED = {"original-code-authority", "source-correspondence", "asset-provenance",
            "brand-clearance", "discogs-permanent-artwork-policy", "discogs-persistent-metadata-policy",
            "discogs-system-display-policy", "notice-delivery", "privacy-contact-review"}
OWNER_DECISIONS = {
    "asset-provenance": (
        "publication/artwork-decision.json", "rights_clearance", "unconfirmed"),
    "discogs-permanent-artwork-policy": (
        "publication/discogs-artwork-decision.json", "provider_permission", "unconfirmed"),
    "discogs-persistent-metadata-policy": (
        "publication/discogs-metadata-decision.json", "provider_permission", "unconfirmed"),
    "brand-clearance": (
        "publication/brand-decision.json", "trademark_clearance", "unconfirmed"),
    "privacy-contact-review": (
        "publication/privacy-contact-decision.json", "review_status", "not-performed"),
}


class ReleaseGateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="publication-gates-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        (self.root / "publication").mkdir()
        (self.root / "docs").mkdir()
        self.evidence = self.root / "docs/approved-synthetic-fixture.txt"
        self.evidence.write_bytes(b"Synthetic test data. Not an actual rights review.")
        self.evidence.chmod(0o644)
        self.row = file_record(self.root, "docs/approved-synthetic-fixture.txt")
        self.value = {"schema": 1, "gates": {name: {"status": "verified",
                      "evidence_files": [self.row]} for name in REQUIRED}}
        self.components = {"schema": 1, "components": []}
        for name in ("aubio", "flac", "ogg", "grdb.swift"):
            source = self.root / "Vendor" / name
            source.mkdir(parents=True)
            (source / "source.txt").write_text("Synthetic source for " + name)
            rows = [file_record(self.root, f"Vendor/{name}/source.txt")]
            self.components["components"].append({
                "id": name, "status": "verified", "source_root": f"Vendor/{name}",
                "source_files": rows, "snapshot_sha256": snapshot_digest(rows),
                "build_files": [self.row], "binary_files": [self.row], "evidence_files": [self.row]})
        self.save_components()
        self.save()

    def save_components(self):
        path = "publication/corresponding-source.json"
        (self.root / path).write_text(json.dumps(self.components))
        self.value["gates"]["source-correspondence"]["evidence_files"] = [file_record(self.root, path)]

    def test_hashing_blocked_component_records_does_not_verify_source(self):
        self.components["components"][0]["status"] = "blocked"
        self.save_components()
        self.save()
        self.fails("Unverified component: aubio")

    def test_source_gate_requires_every_component(self):
        self.components["components"].pop()
        self.save_components()
        self.save()
        self.fails("component set/schema")

    def test_source_gate_checks_actual_component_files(self):
        (self.root / "Vendor/aubio/source.txt").write_text("changed")
        self.fails("Record mismatch")

    def save(self):
        (self.root / GATE_PATH).write_text(json.dumps(self.value))

    def invoke(self):
        return subprocess.run([sys.executable, str(SCRIPT), str(self.root)],
                              env=dict(os.environ, PYTHONDONTWRITEBYTECODE="1"),
                              capture_output=True, text=True, timeout=10)

    def fails(self, message=None):
        before = (self.root / GATE_PATH).read_bytes()
        result = self.invoke()
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertEqual((self.root / GATE_PATH).read_bytes(), before)
        if message:
            self.assertIn(message, result.stderr)

    def test_exact_gate_set_and_schema_are_required(self):
        for mutation in ("missing", "unknown", "schema"):
            with self.subTest(mutation=mutation):
                original = json.loads(json.dumps(self.value))
                if mutation == "missing":
                    del self.value["gates"]["brand-clearance"]
                elif mutation == "unknown":
                    self.value["gates"]["invented"] = {"status": "verified", "evidence_files": [self.row]}
                else:
                    self.value["schema"] = 2
                self.save()
                self.fails("gate set/schema")
                self.value = original

    def test_verified_gate_requires_nonempty_exact_evidence(self):
        self.value["gates"]["brand-clearance"]["evidence_files"] = []
        self.save()
        self.fails("brand-clearance")

    def test_altered_evidence_invalidates_verified_status(self):
        self.evidence.write_bytes(b"altered synthetic evidence")
        self.fails("Record mismatch")

    def test_gate_control_rejects_symlinks_and_hardlinks(self):
        path = self.root / GATE_PATH
        saved = self.root / "saved.json"
        path.rename(saved)
        for kind in ("symlink", "hardlink"):
            with self.subTest(kind=kind):
                if kind == "symlink":
                    path.symlink_to(saved)
                else:
                    os.link(saved, path)
                try:
                    self.fails("link")
                finally:
                    path.unlink()

    def test_duplicate_json_keys_cannot_overwrite_pending_status(self):
        raw = json.dumps(self.value).replace('"status": "verified"',
                    '"status": "pending", "status": "verified"', 1)
        (self.root / GATE_PATH).write_text(raw)
        self.fails("Duplicate JSON")

    def test_excluded_evidence_is_not_read_as_approval(self):
        (self.root / ".env").write_bytes(b"synthetic not a credential")
        row = file_record(self.root, ".env")
        self.value["gates"]["brand-clearance"]["evidence_files"] = [row]
        self.save()
        self.fails("Excluded payload path")

    def test_missing_evidence_rejects_verified_gate(self):
        self.evidence.unlink()
        self.fails("Missing regular file")

    def test_changed_evidence_mode_rejects_verified_gate(self):
        self.evidence.chmod(0o755)
        self.fails("Record mismatch")

    def test_duplicate_evidence_rejects_verified_gate(self):
        self.value["gates"]["brand-clearance"]["evidence_files"] = [self.row, self.row]
        self.save()
        self.fails("Duplicate")

    def test_linked_evidence_rejects_verified_gate(self):
        saved = self.root / "saved-evidence"
        self.evidence.rename(saved)
        self.evidence.symlink_to(saved)
        self.fails("Symlink")
        self.evidence.unlink()
        os.link(saved, self.evidence)
        self.fails("Hardlink")

    def test_pending_gate_stays_blocked_despite_approved_filename(self):
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("does not grant legal rights", result.stdout)
        for name in REQUIRED:
            with self.subTest(name=name):
                self.value["gates"][name]["status"] = "pending"
                self.save()
                self.fails(name)
                self.value["gates"][name]["status"] = "verified"

    def accept_owner_decision(self, gate="discogs-permanent-artwork-policy"):
        name, claim_field, claim_status = OWNER_DECISIONS[gate]
        (self.root / name).write_text(json.dumps({
            "schema": 1, "gate": gate,
            "decision": "nonblocking", claim_field: claim_status,
            "owner_instruction": "Synthetic owner decision for this test only."
        }))
        self.value["gates"][gate] = {
            "status": "owner-nonblocking", "evidence_files": [file_record(self.root, name)]}
        self.save()
        return name

    def test_each_owner_decision_is_nonblocking_without_claiming_permission(self):
        for gate in OWNER_DECISIONS:
            with self.subTest(gate=gate):
                self.accept_owner_decision(gate)
                result = self.invoke()
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn(gate, result.stdout)
                if gate.startswith("discogs-"):
                    self.assertIn("provider permission remains unconfirmed", result.stdout)
                saved = json.loads((self.root / GATE_PATH).read_text())
                self.assertEqual(saved["gates"][gate]["status"], "owner-nonblocking")
                self.value["gates"][gate] = {"status": "verified", "evidence_files": [self.row]}

    def test_owner_decision_cannot_waive_other_gates(self):
        for approved in OWNER_DECISIONS:
            self.accept_owner_decision(approved)
            for name in REQUIRED - {approved}:
                with self.subTest(approved=approved, gate=name):
                    self.value["gates"][name] = dict(self.value["gates"][approved])
                    self.save()
                    self.fails(name)
                    self.value["gates"][name] = {"status": "verified", "evidence_files": [self.row]}
                    if name == "source-correspondence":
                        self.save_components()
            self.value["gates"][approved] = {"status": "verified", "evidence_files": [self.row]}

    def test_owner_decision_requires_bound_explicit_record(self):
        for gate in OWNER_DECISIONS:
            with self.subTest(gate=gate):
                name = self.accept_owner_decision(gate)
                self.value["gates"][gate]["evidence_files"] = [self.row]
                self.save()
                self.fails("decision")
                self.accept_owner_decision(gate)
                (self.root / name).write_text("changed owner evidence")
                self.fails("Record mismatch")
                self.value["gates"][gate] = {"status": "verified", "evidence_files": [self.row]}

    def test_owner_decision_cannot_claim_unverified_permission_or_review(self):
        for gate in OWNER_DECISIONS:
            _, claim_field, _ = OWNER_DECISIONS[gate]
            name = self.accept_owner_decision(gate)
            path = self.root / name
            value = json.loads(path.read_text())
            for field, replacement in (("gate", "source-correspondence"), ("decision", "pending"),
                                       (claim_field, "verified"), ("owner_instruction", ""),
                                       ("schema", True)):
                with self.subTest(gate=gate, field=field):
                    path.write_text(json.dumps(dict(value, **{field: replacement})))
                    self.value["gates"][gate]["evidence_files"] = [file_record(self.root, name)]
                    self.save()
                    self.fails("decision")
            self.value["gates"][gate] = {"status": "verified", "evidence_files": [self.row]}

    def test_policies_require_independent_decisions(self):
        for approved in OWNER_DECISIONS:
            self.accept_owner_decision(approved)
            for pending in OWNER_DECISIONS.keys() - {approved}:
                with self.subTest(approved=approved, pending=pending):
                    self.value["gates"][pending]["status"] = "pending"
                    self.save()
                    self.fails(pending)
                    self.value["gates"][pending]["status"] = "verified"
            for gate in OWNER_DECISIONS:
                self.value["gates"][gate] = {"status": "verified", "evidence_files": [self.row]}

    def test_all_owner_decisions_can_be_nonblocking(self):
        for gate in OWNER_DECISIONS:
            self.accept_owner_decision(gate)
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Owner-nonblocking: " + ", ".join(sorted(OWNER_DECISIONS)), result.stdout)
