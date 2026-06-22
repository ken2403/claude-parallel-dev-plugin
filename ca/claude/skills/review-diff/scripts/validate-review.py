#!/usr/bin/env python3
"""Validate a ca_claude_review.v1 review JSON. Fail-closed: any problem -> exit 1.

Usage: validate-review.py <review.json>
On success: prints the verdict and exits 0.
On schema violation: prints the reason to stderr and exits 1 (caller treats as blocked).
On missing file / parse error: exits 2.
"""
import json
import sys

VERDICTS = {"approve", "request_changes", "blocked"}
SEVERITIES = {"blocker", "major", "minor"}


def fail(msg):
    print(f"review invalid: {msg}", file=sys.stderr)
    sys.exit(1)


def main():
    if len(sys.argv) != 2:
        print("usage: validate-review.py <review.json>", file=sys.stderr)
        sys.exit(2)
    try:
        d = json.load(open(sys.argv[1]))
    except FileNotFoundError:
        print(f"review file not found: {sys.argv[1]}", file=sys.stderr)
        sys.exit(2)
    except Exception as e:
        print(f"parse error: {e}", file=sys.stderr)
        sys.exit(2)

    if not isinstance(d, dict):
        fail("top level must be an object")
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
        if "severity" in f and f["severity"] not in SEVERITIES:
            fail(f"findings[{i}].severity must be one of {sorted(SEVERITIES)}")
        if not isinstance(f.get("title", ""), str):
            fail(f"findings[{i}].title must be a string")

    print(d["verdict"])
    sys.exit(0)


if __name__ == "__main__":
    main()
