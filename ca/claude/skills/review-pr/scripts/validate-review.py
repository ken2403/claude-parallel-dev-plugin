#!/usr/bin/env python3
"""Validate a ca_claude_review.v1 review JSON. Fail-closed: any problem -> exit 1.

Usage: validate-review.py <review.json> [blind-review.json]
On success: prints the verdict and exits 0.
On schema violation: prints the reason to stderr and exits 1 (caller treats as blocked).
On missing file / parse error: exits 2.
"""
import json
import re
import sys

VERDICTS = {"approve", "request_changes", "blocked"}
SEVERITIES = {"blocker", "major", "minor"}
MODES = {"checkpoint", "final"}
PRODUCERS = {"blind", "synthesis"}
SECOND_OPINION_STATUSES = {"used", "clean_no_synthesis", "unavailable", "invalid", "disabled"}
COVERAGES = {"full", "partial"}
ADJUDICATIONS = {"confirmed", "refuted", "not_applicable", "unresolved_missing_evidence"}
RESOLVED_SEVERITIES = {"minor", "none"}
FINDING_ID_RE = re.compile(r"^[CX][0-9]{3}$")
BLIND_FINDING_ID_RE = re.compile(r"^C[0-9]{3}$")


def fail(msg):
    print(f"review invalid: {msg}", file=sys.stderr)
    sys.exit(1)


def load_json(path):
    try:
        return json.load(open(path))
    except FileNotFoundError:
        print(f"review file not found: {path}", file=sys.stderr)
        sys.exit(2)
    except Exception as e:
        print(f"parse error: {e}", file=sys.stderr)
        sys.exit(2)


def require_string(obj, key, ctx, max_len=None):
    value = obj.get(key)
    if not isinstance(value, str):
        fail(f"{ctx}.{key} must be a string")
    if max_len is not None and len(value) > max_len:
        fail(f"{ctx}.{key} is too long")
    return value


def validate_second_opinion(value):
    if not isinstance(value, dict):
        fail("second_opinion must be an object")
    allowed = {"provider", "status", "coverage", "ledger", "prior_findings_rechecked", "notes"}
    extra = set(value) - allowed
    if extra:
        fail(f"second_opinion has unknown keys: {sorted(extra)}")
    if value.get("provider") != "codex":
        fail("second_opinion.provider must be codex")
    if value.get("status") not in SECOND_OPINION_STATUSES:
        fail(f"second_opinion.status must be one of {sorted(SECOND_OPINION_STATUSES)}")
    if value.get("coverage") not in COVERAGES:
        fail(f"second_opinion.coverage must be one of {sorted(COVERAGES)}")
    ledger = value.get("ledger")
    if not isinstance(ledger, list):
        fail("second_opinion.ledger must be a list")
    for i, item in enumerate(ledger):
        if not isinstance(item, dict):
            fail(f"second_opinion.ledger[{i}] must be an object")
        allowed_item = {"id", "adjudication", "evidence"}
        extra = set(item) - allowed_item
        if extra:
            fail(f"second_opinion.ledger[{i}] has unknown keys: {sorted(extra)}")
        if not re.match(r"^X[0-9]{3}$", item.get("id", "")):
            fail(f"second_opinion.ledger[{i}].id must match XNNN")
        if item.get("adjudication") not in ADJUDICATIONS:
            fail(f"second_opinion.ledger[{i}].adjudication must be one of {sorted(ADJUDICATIONS)}")
        require_string(item, "evidence", f"second_opinion.ledger[{i}]", 4000)
    if not isinstance(value.get("prior_findings_rechecked"), bool):
        fail("second_opinion.prior_findings_rechecked must be a boolean")
    if "notes" in value and not isinstance(value["notes"], str):
        fail("second_opinion.notes must be a string")


def validate_resolved_blind_findings(value):
    if not isinstance(value, list):
        fail("resolved_blind_findings must be a list")
    for i, item in enumerate(value):
        if not isinstance(item, dict):
            fail(f"resolved_blind_findings[{i}] must be an object")
        allowed = {"id", "reason", "evidence", "new_severity"}
        extra = set(item) - allowed
        if extra:
            fail(f"resolved_blind_findings[{i}] has unknown keys: {sorted(extra)}")
        if not re.match(r"^C[0-9]{3}$", item.get("id", "")):
            fail(f"resolved_blind_findings[{i}].id must match CNNN")
        require_string(item, "reason", f"resolved_blind_findings[{i}]", 1000)
        require_string(item, "evidence", f"resolved_blind_findings[{i}]", 4000)
        if item.get("new_severity") not in RESOLVED_SEVERITIES:
            fail(f"resolved_blind_findings[{i}].new_severity must be one of {sorted(RESOLVED_SEVERITIES)}")


def enforce_no_silent_drop(synth, blind):
    for i, f in enumerate(blind.get("findings", [])):
        if not isinstance(f, dict) or f.get("blocking") is not True:
            continue
        if not isinstance(f.get("id"), str) or not BLIND_FINDING_ID_RE.match(f["id"]):
            fail(f"blind findings[{i}].id must match CNNN for blocking findings")
    blind_ids = {
        f.get("id")
        for f in blind.get("findings", [])
        if isinstance(f, dict) and f.get("blocking") is True
    }
    if not blind_ids:
        return
    final_ids = {
        f.get("id")
        for f in synth.get("findings", [])
        if isinstance(f, dict) and isinstance(f.get("id"), str)
    }
    resolved_ids = {
        f.get("id")
        for f in synth.get("resolved_blind_findings", [])
        if isinstance(f, dict) and isinstance(f.get("id"), str)
    }
    missing = sorted(blind_ids - final_ids - resolved_ids)
    if missing:
        fail(f"synthesis silently dropped blind blocking findings: {missing}")


def main():
    if len(sys.argv) not in (2, 3):
        print("usage: validate-review.py <review.json> [blind-review.json]", file=sys.stderr)
        sys.exit(2)
    d = load_json(sys.argv[1])
    blind = load_json(sys.argv[2]) if len(sys.argv) == 3 else None

    if not isinstance(d, dict):
        fail("top level must be an object")
    if "schema_version" in d and d["schema_version"] != "ca_claude_review.v1":
        fail("schema_version must be ca_claude_review.v1")
    if "mode" in d and d["mode"] not in MODES:
        fail(f"mode must be one of {sorted(MODES)}")
    if "producer" in d and d["producer"] not in PRODUCERS:
        fail(f"producer must be one of {sorted(PRODUCERS)}")
    if d.get("verdict") not in VERDICTS:
        fail(f"verdict must be one of {sorted(VERDICTS)}")
    findings = d.get("findings")
    if not isinstance(findings, list):
        fail("findings must be a list")
    for i, f in enumerate(findings):
        if not isinstance(f, dict):
            fail(f"findings[{i}] must be an object")
        if not isinstance(f.get("blocking"), bool):
            fail(f"findings[{i}].blocking must be a boolean")
        if not isinstance(f.get("id"), str) or not FINDING_ID_RE.match(f["id"]):
            fail(f"findings[{i}].id must match CNNN or XNNN")
        if "severity" in f and f["severity"] not in SEVERITIES:
            fail(f"findings[{i}].severity must be one of {sorted(SEVERITIES)}")
        if not isinstance(f.get("title", ""), str):
            fail(f"findings[{i}].title must be a string")
    if "second_opinion" in d:
        validate_second_opinion(d["second_opinion"])
    if "resolved_blind_findings" in d:
        validate_resolved_blind_findings(d["resolved_blind_findings"])
    if d.get("producer") == "synthesis" and blind is not None:
        enforce_no_silent_drop(d, blind)

    print(d["verdict"])
    sys.exit(0)


if __name__ == "__main__":
    main()
