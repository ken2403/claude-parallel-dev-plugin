#!/usr/bin/env bash
# ==============================================================================
# PreToolUse(Edit|Write|NotebookEdit) guard: block edits to sensitive files.
#
# Reads the hook JSON payload on stdin, extracts the target file path, and
# exits 2 (blocking, stderr fed back to Claude) when the path looks like a
# secret/credential file. @@GUARD_CONTEXT_BLOCK@@
#
# Exit 0 = allow, exit 2 = block.
@@GUARD_FOOTER_BLOCK@@
set -uo pipefail

payload="$(cat 2>/dev/null || true)"

# Extract tool_input.file_path without a hard jq dependency.
if command -v jq >/dev/null 2>&1; then
  file_path="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"
else
  file_path="$(printf '%s' "$payload" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')"
fi
[ -z "$file_path" ] && exit 0

base="$(basename "$file_path")"
# Patterns matched case-sensitively against the full path or basename.
for pat in '.env' '.env.' 'credentials' 'secret' 'id_rsa' 'id_ed25519' '.pem' '.p12' '.pfx' '.keystore'; do
  case "$file_path" in *"$pat"*) blocked=1;; esac
  case "$base" in *"$pat"*) blocked=1;; esac
done
# Allow obvious template/example files.
case "$base" in *.example|*.sample|*.template|*.dist) blocked="";; esac

if [ -n "${blocked:-}" ]; then
  echo "@@PLUGIN@@: refusing to edit sensitive file '$file_path'. If this is intentional, edit it manually or remove it from the guard list." >&2
  exit 2
fi
exit 0
