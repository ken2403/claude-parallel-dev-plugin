#!/usr/bin/env python3
"""Validate an hv feature manifest before launch.

The manifest is the plan that guarantees non-interference: features must be
file-disjoint (so parallel worktrees never touch the same file) and their
dependency graph must be acyclic (so launch waves terminate). That guarantee is
safety-critical, so it is checked mechanically here rather than by eye — a
missed file collision is exactly the kind of error that silently corrupts a
parallel run.

Usage:  validate_manifest.py <manifest.json>

Exits 0 and prints "OK: ..." on success.
Exits 1 and prints specific, actionable errors on failure.
Exits 2 on a usage error.
"""
import json
import sys

REQUIRED_FIELDS = ["id", "branch", "scope", "target_files", "success_criteria"]


def validate(manifest):
    """Return a list of human-readable error strings (empty == valid)."""
    errors = []

    features = manifest.get("features")
    if not isinstance(features, list) or not features:
        return ["manifest has no non-empty 'features' array"]

    # Required fields + id collection.
    ids = []
    for i, feat in enumerate(features):
        if not isinstance(feat, dict):
            errors.append(f"feature at index {i} is not an object")
            continue
        fid = feat.get("id") or f"<index {i}>"
        for key in REQUIRED_FIELDS:
            if not feat.get(key):
                errors.append(f"feature '{fid}': missing required field '{key}'")
        if feat.get("id"):
            ids.append(feat["id"])

    for dup in sorted({x for x in ids if ids.count(x) > 1}):
        errors.append(f"duplicate feature id: '{dup}'")

    # File-disjointness — the core non-interference guarantee.
    file_owner = {}
    for feat in features:
        if not isinstance(feat, dict):
            continue
        fid = feat.get("id", "?")
        for target in feat.get("target_files", []) or []:
            if target in file_owner:
                errors.append(
                    f"file collision: '{target}' is claimed by both "
                    f"'{file_owner[target]}' and '{fid}' — parallel features must be "
                    "file-disjoint; merge them into one feature or sequence them "
                    "with depends_on"
                )
            else:
                file_owner[target] = fid

    # depends_on must resolve and be acyclic.
    id_set = set(ids)
    graph = {}
    for feat in features:
        if not isinstance(feat, dict):
            continue
        fid = feat.get("id")
        if not fid:
            continue
        deps = feat.get("depends_on", []) or []
        for dep in deps:
            if dep not in id_set:
                errors.append(
                    f"feature '{fid}': depends_on '{dep}', which is not a feature "
                    "in this manifest"
                )
        graph[fid] = [d for d in deps if d in id_set]

    # Cycle detection via DFS coloring.
    WHITE, GRAY, BLACK = 0, 1, 2
    color = {n: WHITE for n in graph}
    cycles = []

    def visit(node, stack):
        color[node] = GRAY
        for nxt in graph.get(node, []):
            if color.get(nxt) == GRAY:
                cycles.append(" -> ".join(stack + [nxt]))
            elif color.get(nxt) == WHITE:
                visit(nxt, stack + [nxt])
        color[node] = BLACK

    for node in graph:
        if color[node] == WHITE:
            visit(node, [node])
    for cyc in cycles:
        errors.append(f"dependency cycle: {cyc}")

    return errors


def count_waves(manifest):
    """Number of dependency waves (independent features = wave 1)."""
    features = manifest["features"]
    id_set = {f["id"] for f in features if isinstance(f, dict) and f.get("id")}
    remaining = {
        f["id"]: [d for d in (f.get("depends_on") or []) if d in id_set]
        for f in features
        if isinstance(f, dict) and f.get("id")
    }
    done, waves = set(), 0
    while remaining:
        ready = [n for n, deps in remaining.items() if all(d in done for d in deps)]
        if not ready:
            return None  # cycle — already reported by validate()
        waves += 1
        for n in ready:
            done.add(n)
            del remaining[n]
    return waves


def main(path):
    try:
        with open(path) as f:
            manifest = json.load(f)
    except FileNotFoundError:
        print(f"ERROR: manifest not found: {path}")
        return 1
    except json.JSONDecodeError as e:
        print(f"ERROR: manifest is not valid JSON: {e}")
        return 1

    errors = validate(manifest)
    if errors:
        print(f"INVALID manifest ({len(errors)} problem(s)):")
        for err in errors:
            print(f"  - {err}")
        return 1

    waves = count_waves(manifest)
    file_count = sum(
        len(f.get("target_files") or [])
        for f in manifest["features"]
        if isinstance(f, dict)
    )
    print(
        f"OK: {len(manifest['features'])} features, {waves} wave(s), "
        f"{file_count} target files — no collisions or cycles"
    )
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: validate_manifest.py <manifest.json>")
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
