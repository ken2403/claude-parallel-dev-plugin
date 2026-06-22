#!/usr/bin/env bash
# Send a prompt to Codex for an adversarial "sparring" critique and print its reply.
# Read-only sandbox (no edits), high reasoning. Override the binary with CODEX_BIN
# if `codex` is not on PATH (e.g. a version-manager shim).
#
# Usage: spar-codex.sh <prompt-file>
set -euo pipefail
PROMPT_FILE="${1:?usage: spar-codex.sh <prompt-file>}"
[ -f "$PROMPT_FILE" ] || { echo "prompt file not found: $PROMPT_FILE" >&2; exit 1; }
"${CODEX_BIN:-codex}" exec --sandbox read-only -c model_reasoning_effort=high - < "$PROMPT_FILE" 2>/dev/null
