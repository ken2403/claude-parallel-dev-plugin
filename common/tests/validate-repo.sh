#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
PYTHONPYCACHEPREFIX="$(mktemp -d "${TMPDIR:-/tmp}/validate-pycache.XXXXXX")"
export PYTHONPYCACHEPREFIX
trap 'rm -rf "$PYTHONPYCACHEPREFIX"' EXIT

fail() {
  echo "validate-repo: $*" >&2
  exit 1
}

echo "== generated files =="
bash common/sync.sh --check
bash common/tests/run.sh

echo "== plugin validation =="
CLAUDE_BIN="${CLAUDE_BIN:-claude}"
if command -v "$CLAUDE_BIN" >/dev/null 2>&1; then
  "$CLAUDE_BIN" plugin validate ./ha
  "$CLAUDE_BIN" plugin validate ./sa
  "$CLAUDE_BIN" plugin validate ./ca/claude
else
  if [ "${ALLOW_MISSING_CLAUDE_VALIDATE:-0}" = "1" ]; then
    echo "::warning::Claude CLI not available; skipping 'claude plugin validate' in this environment."
    echo "Plugin validation was not silently treated as run. Install Claude Code and run:"
    echo "  claude plugin validate ./ha"
    echo "  claude plugin validate ./sa"
    echo "  claude plugin validate ./ca/claude"
  else
    fail "claude CLI is required for plugin validation; set ALLOW_MISSING_CLAUDE_VALIDATE=1 only in CI environments that intentionally degrade this check"
  fi
fi

echo "== manifests =="
python3 -m json.tool .claude-plugin/marketplace.json >/dev/null
for plugin in ha sa ca/claude ca/codex; do
  manifest="$plugin/.claude-plugin/plugin.json"
  [ -f "$manifest" ] || manifest="$plugin/.codex-plugin/plugin.json"
  [ -f "$manifest" ] || fail "missing plugin manifest for $plugin"
  python3 -m json.tool "$manifest" >/dev/null
done
[ ! -e common/.claude-plugin ] || fail "common/ must not be a Claude plugin"
[ ! -e common/.codex-plugin ] || fail "common/ must not be a Codex plugin"
[ ! -e common/plugin.json ] || fail "common/ must not be a plugin"

echo "== syntax =="
while IFS= read -r sh_file; do
  bash -n "$sh_file"
done < <(find ha sa ca common -type f -name '*.sh' | sort)
while IFS= read -r py_file; do
  python3 -m py_compile "$py_file"
done < <(find ha sa ca common -type f -name '*.py' | sort)

echo "== ca contract copies =="
cmp -s ca/claude/skills/review-pr/references/review-contract.md \
  ca/codex/skills/ca-implement-plan/references/review-contract.md \
  || fail "ca review-contract.md copies must be byte-identical"

echo "== skill and agent identity =="
while IFS= read -r skill; do
  dir="$(basename "$(dirname "$skill")")"
  name="$(awk '/^---$/ { fm++; next } fm == 1 && /^name:/ { sub(/^name:[[:space:]]*/, ""); print; exit }' "$skill")"
  [ "$name" = "$dir" ] || fail "$skill has name '$name', expected '$dir'"
done < <(find ha/skills sa/skills ca/claude/skills ca/codex/skills -name SKILL.md | sort)

while IFS= read -r agent; do
  file="$(basename "$agent" .md)"
  name="$(awk '/^name:/ { sub(/^name:[[:space:]]*/, ""); print; exit }' "$agent")"
  [ "$name" = "$file" ] || fail "$agent has name '$name', expected '$file'"
done < <(find ha/agents sa/agents -name '*.md' | sort)

echo "== skill body length =="
while IFS= read -r skill; do
  body_lines="$(awk 'BEGIN { fm=0; body=0 } /^---$/ { fm++; next } fm >= 2 { body++ } END { print body }' "$skill")"
  [ "$body_lines" -le 500 ] || fail "$skill body has $body_lines lines; keep it <= 500"
done < <(find ha/skills sa/skills ca/claude/skills ca/codex/skills -name SKILL.md | sort)

echo "== generated modes and symlinks =="
[ -L CLAUDE.md ] || fail "CLAUDE.md must remain a symlink to AGENTS.md"
[ "$(readlink CLAUDE.md)" = "AGENTS.md" ] || fail "CLAUDE.md must point to AGENTS.md"
while IFS=$'\t' read -r class _src dest; do
  [ -z "${class:-}" ] && continue
  case "$class" in \#*) continue ;; esac
  mode="$(git ls-files -s -- "$dest" | awk '{print $1}')"
  [ -n "$mode" ] || fail "$dest is not tracked"
  [ "$mode" != "120000" ] || fail "$dest must not be a symlink"
  case "$class" in
    script) [ "$mode" = "100755" ] || fail "$dest mode is $mode; expected 100755" ;;
    reference|skill) [ "$mode" = "100644" ] || fail "$dest mode is $mode; expected 100644" ;;
    *) fail "unknown manifest class '$class'" ;;
  esac
done < common/manifest.tsv

echo "validate-repo: ok"
