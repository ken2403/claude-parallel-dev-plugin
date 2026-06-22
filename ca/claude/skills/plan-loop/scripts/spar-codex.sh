#!/usr/bin/env bash
# Send a prompt to Codex for an adversarial "sparring" critique and print its reply.
# Read-only sandbox (no edits), high reasoning. Override the binary with CODEX_BIN
# if `codex` is not on PATH (e.g. a version-manager shim).
#
# Usage: spar-codex.sh <prompt-file>
# Fails loudly (non-zero) with the captured stderr if Codex cannot run, rather than
# silently returning an empty critique.
set -euo pipefail
CODEX_BIN="${CODEX_BIN:-codex}"
PROMPT_FILE="${1:?usage: spar-codex.sh <prompt-file>}"
[ -f "$PROMPT_FILE" ] || { echo "prompt file not found: $PROMPT_FILE" >&2; exit 1; }
command -v "$CODEX_BIN" >/dev/null 2>&1 || {
  echo "spar-codex: '$CODEX_BIN' not found on PATH. Set CODEX_BIN or install Codex." >&2; exit 1; }

ERR="$(mktemp)"; trap 'rm -f "$ERR"' EXIT
if ! out="$("$CODEX_BIN" exec --sandbox read-only -c model_reasoning_effort=high - < "$PROMPT_FILE" 2>"$ERR")"; then
  echo "spar-codex: codex exec failed:" >&2; cat "$ERR" >&2; exit 1
fi
[ -n "$out" ] || { echo "spar-codex: codex returned no output:" >&2; cat "$ERR" >&2; exit 1; }
printf '%s\n' "$out"
