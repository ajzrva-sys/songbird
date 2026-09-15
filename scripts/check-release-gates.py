#!/usr/bin/env python3
"""Check evidence identity, not its legal sufficiency; never changes status."""
from pathlib import Path
import sys
from publication_checks import indexed, load_json, safe_payload_name, verify_rows, verify_component

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


def check(root):
    root = Path(root).absolute()
    value = load_json(root, "publication/release-gates.json")
    if (type(value.get("schema")) is not int or value["schema"] != 1
            or not isinstance(value.get("gates"), dict) or set(value["gates"]) != REQUIRED):
        raise ValueError("Release gate set/schema mismatch")
    blocked = []
    nonblocking = []
    for name in sorted(REQUIRED):
        gate = value["gates"][name]
        owner_decision = name in OWNER_DECISIONS and gate.get("status") == "owner-nonblocking"
        if (gate.get("status") != "verified" and not owner_decision) or not gate.get("evidence_files"):
            blocked.append(name)
            continue
        evidence = indexed(gate["evidence_files"])
        for path in evidence:
            safe_payload_name(path)
        verify_rows(root, gate["evidence_files"])
        if name == "source-correspondence":
            component_path = "publication/corresponding-source.json"
            if component_path not in evidence:
                raise ValueError("Source correspondence requires bound component records")
            records = load_json(root, component_path)
            components = records.get("components")
            if (type(records.get("schema")) is not int or records["schema"] != 1
                    or not isinstance(components, list) or len(components) != 4
                    or {row["id"] for row in components} != {"aubio", "flac", "ogg", "grdb.swift"}):
                raise ValueError("Source component set/schema mismatch")
            for component in components:
                verify_component(root, component)
        if owner_decision:
            decision_path, claim_field, claim_status = OWNER_DECISIONS[name]
            if decision_path not in evidence:
                raise ValueError(f"Missing bound owner decision for {name}")
            decision = load_json(root, decision_path)
            if (type(decision.get("schema")) is not int or decision["schema"] != 1
                    or decision.get("gate") != name
                    or decision.get("decision") != "nonblocking"
                    or decision.get(claim_field) != claim_status
                    or not isinstance(decision.get("owner_instruction"), str)
                    or not decision["owner_instruction"].strip()):
                raise ValueError(f"Invalid owner decision for {name}")
            nonblocking.append(name)
    if nonblocking:
        print("Owner-nonblocking: " + ", ".join(sorted(nonblocking)), flush=True)
        if any(name.startswith("discogs-") for name in nonblocking):
            print("Discogs provider permission remains unconfirmed", flush=True)
    if blocked:
        raise ValueError("Release blocked: " + ", ".join(sorted(blocked)))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: check-release-gates.py ROOT")
    try:
        check(sys.argv[1])
    except (ValueError, OSError, KeyError, TypeError) as error:
        raise SystemExit(str(error))
    print("Release gate records checked; this check does not grant legal rights")
