#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

fail() {
  echo "validate-repo: $*" >&2
  exit 1
}

echo "== generated files =="
bash common/sync.sh --check
bash common/tests/run.sh

echo "== plugin validation =="
command -v claude >/dev/null 2>&1 || fail "claude CLI is required for plugin validation"
claude plugin validate ./ha
claude plugin validate ./sa
claude plugin validate ./ca/claude

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
