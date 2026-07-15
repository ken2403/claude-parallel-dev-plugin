#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SYNC="$ROOT/common/sync.sh"
TMP_ROOT="${TMPDIR:-/tmp}/common-sync-tests.$$"
trap 'rm -rf "$TMP_ROOT"' EXIT

pass_count=0

make_repo() {
  local dir="$1"
  mkdir -p "$dir/repo/common/src/skills/demo" \
    "$dir/repo/common/plugins/ha/fragments/demo" \
    "$dir/repo/ha/skills/demo"
  git -C "$dir/repo" init -q
  git -C "$dir/repo" config user.email "common-sync-tests@example.invalid"
  git -C "$dir/repo" config user.name "Common Sync Tests"
  cat > "$dir/repo/common/plugins/ha/vars" <<'EOF'
PLUGIN=ha
PLUGIN_UPPER=HA
DEMO_DESCRIPTION=Demo description
EOF
  cat > "$dir/repo/common/src/skills/demo/SKILL.md" <<'EOF'
---
name: demo
description: @@DESCRIPTION@@
---
@@FRAGMENT:body@@
@@PLUGIN@@
EOF
  cat > "$dir/repo/common/plugins/ha/fragments/demo/body.md" <<'EOF'
body
EOF
  cat > "$dir/repo/common/manifest.tsv" <<'EOF'
skill	src/skills/demo/SKILL.md	ha/skills/demo/SKILL.md
EOF
  cat > "$dir/repo/common/exclusions.tsv" <<'EOF'
EOF
  cat > "$dir/repo/ha/skills/demo/SKILL.md" <<'EOF'
---
name: demo
description: Demo description
---
body
ha
EOF
  git -C "$dir/repo" add .
  git -C "$dir/repo" commit -q -m init
}

run_expect_fail() {
  local name="$1" expected="$2"
  shift 2
  local dir="$TMP_ROOT/$name"
  make_repo "$dir"
  "$@" "$dir/repo"
  set +e
  output="$(COMMON_SYNC_SKIP_COVERAGE=1 COMMON_ROOT="$dir/repo/common" REPO_ROOT="$dir/repo" bash "$SYNC" --check 2>&1)"
  status=$?
  set -e
  if [ "$status" -eq 0 ]; then
    echo "FAIL $name: expected failure" >&2
    exit 1
  fi
  if [[ "$output" != *"$expected"* ]]; then
    echo "FAIL $name: expected output containing '$expected'" >&2
    echo "$output" >&2
    exit 1
  fi
  echo "ok - $name"
  pass_count=$((pass_count + 1))
}

run_expect_pass() {
  local name="$1"
  local dir="$TMP_ROOT/$name"
  make_repo "$dir"
  output="$(COMMON_SYNC_SKIP_COVERAGE=1 COMMON_ROOT="$dir/repo/common" REPO_ROOT="$dir/repo" bash "$SYNC" --check 2>&1)"
  [[ "$output" == *"up to date"* ]]
  echo "ok - $name"
  pass_count=$((pass_count + 1))
}

assert_contains_normalized() {
  local file="$1" needle="$2"
  python3 - "$file" "$needle" <<'PY'
import re, sys
path, needle = sys.argv[1:]
text = open(path, encoding="utf-8").read()
norm_text = re.sub(r"\s+", " ", text)
norm_needle = re.sub(r"\s+", " ", needle)
if norm_needle not in norm_text:
    print(f"FAIL safety string missing from {path}: {needle}", file=sys.stderr)
    sys.exit(1)
PY
  echo "ok - safety string: $file"
  pass_count=$((pass_count + 1))
}

run_expect_pass baseline
run_expect_fail missing-fragment "missing fragment" \
  bash -c 'rm "$1/common/plugins/ha/fragments/demo/body.md"' --
run_expect_fail unused-fragment "unused fragment" \
  bash -c 'printf "unused\n" > "$1/common/plugins/ha/fragments/demo/unused.md"' --
run_expect_fail stale-output "stale generated file" \
  bash -c 'printf "stale\n" > "$1/ha/skills/demo/SKILL.md"' --
run_expect_fail unknown-manifest-class "unknown manifest class" \
  bash -c 'perl -0pi -e "s/^skill/weird/" "$1/common/manifest.tsv"' --
run_expect_fail wrong-column-count "expected exactly 3" \
  bash -c 'printf "skill\tsrc/skills/demo/SKILL.md\tha/skills/demo/SKILL.md\textra\n" > "$1/common/manifest.tsv"' --
run_expect_fail missing-destination "missing destination" \
  bash -c 'rm "$1/ha/skills/demo/SKILL.md"' --
run_expect_fail unknown-var "unknown variable" \
  bash -c 'printf "@@MISSING@@\n" >> "$1/common/src/skills/demo/SKILL.md"' --
run_expect_fail nested-fragment "nested fragment" \
  bash -c 'printf "@@FRAGMENT:other@@\n" > "$1/common/plugins/ha/fragments/demo/body.md"; printf "other\n" > "$1/common/plugins/ha/fragments/demo/other.md"' --

assert_contains_normalized "$ROOT/ca/claude/skills/merge-pr/SKILL.md" "the draft state IS the review gate"
assert_contains_normalized "$ROOT/ha/skills/merge-pr/SKILL.md" "Do NOT require APPROVED"
assert_contains_normalized "$ROOT/sa/skills/merge-pr/SKILL.md" "Do NOT require APPROVED"
assert_contains_normalized "$ROOT/ha/skills/merge-pr/SKILL.md" "superpowers:finishing-a-development-branch"
assert_contains_normalized "$ROOT/ca/claude/skills/clean-worktrees/SKILL.md" "including a draft still in the ca loop"
assert_contains_normalized "$ROOT/ha/skills/code-review/SKILL.md" "money/billing; external-input parsing"
assert_contains_normalized "$ROOT/sa/skills/code-review/SKILL.md" "money/billing; external-input parsing"
assert_contains_normalized "$ROOT/ha/skills/code-review/SKILL.md" "behavior change without a covering test"
assert_contains_normalized "$ROOT/sa/skills/code-review/SKILL.md" "behavior change without a covering test"
assert_contains_normalized "$ROOT/ha/skills/code-review/SKILL.md" "references/test-rigor.md"
assert_contains_normalized "$ROOT/sa/skills/code-review/SKILL.md" "references/test-rigor.md"

echo "common/tests/run.sh: $pass_count tests passed"
