# cx — Claude × Codex Plan→Implement→Review Loop Plugin — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship one plugin directory (`cx/`) that drives a seamless loop — Claude drafts a plan (sparring with Codex), Codex implements it in an isolated git worktree, Claude reviews the diff, Codex applies feedback over a few rounds, a PR is opened with an exchange summary, and the worktree is cleaned up after a human merges.

**Architecture:** A fixed shell driver (`scripts/run-loop.sh`) owns control-flow. It creates a worktree off `main`, then alternates: `codex exec` (implement one round, sandboxed `workspace-write`, no network) → host-side `claude -p "/cx:review-diff"` (review the diff → schema-validated JSON). State lives in files (plan.md, `review-round-N.json`, git diff); Codex continuity is a *hybrid* optimization via an explicit captured `thread_id` (never `--last`). After convergence the driver opens the PR, posts the exchange summary, and a watcher cleans the worktree on merge.

**Tech Stack:** Bash, `python3` (JSON-schema validation, no external deps), `git worktree`, `gh` CLI, Claude Code plugin (skills/agents), Codex CLI `codex exec` (`--output-schema`, `--json`, `resume <id>`, `-C`, `-s`).

---

## Background: verified facts this plan relies on

Confirmed on the dev machine (codex-cli 0.128.0, claude 2.1.162, gh 2.87.3) during feasibility:

- `codex exec` flags present: `-s/--sandbox`, `-C/--cd`, `--skip-git-repo-check`, `--output-schema <FILE>`, `--json`, `-o/--output-last-message <FILE>`, `resume [SESSION_ID|--last] [PROMPT]`, `-c key=value`, `-m`.
- `codex exec` has **no** `-a/--ask-for-approval`; set approval via `-c approval_policy=never` or a profile.
- `codex exec --json` emits a `thread.started` event whose `thread_id` is the session id to resume by. `resume --last` is **race-prone** across terminals — always resume by captured `thread_id`. (Demonstrated: explicit id continues the right session; `--last` grabbed an interleaving session.)
- `codex exec --output-schema` reliably forces JSON conforming to a given JSON Schema (demonstrated round-trip).
- Codex skills auto-discover from `$REPO_ROOT/.agents/skills`, but this plan invokes the skill by **absolute path in the prompt** for deterministic headless firing (does not rely on auto-discovery).
- Claude `claude -p "<prompt>"` runs headless; `/cx:review-diff` is a plugin slash command available when the `cx` plugin is installed.
- Reuse target: the existing `hv/` plugin already implements plan/build/review/cleanup for the Claude-only flow; `cx` borrows its review *criteria* (`hv/skills/review-pr/SKILL.md`) and its watch/cleanup *shape* (`hv/scripts/watch-merge.sh`, `hv/agents/janitor.md`) but does **not** depend on hv's `claude --bg` auto-worktree (Codex does not auto-isolate; the driver makes the worktree explicitly).

## Adopted decisions (from Claude×Codex sparring)

1. **Driver = fixed script** (`run-loop.sh`) owns the loop; the Codex skill does one round only (stateless responsibility, file-fed).
2. **Worktree owned by the script**, not the model: `git worktree add -b cx/<id> <wt> origin/main`; removed by the watcher after merge.
3. **Plan is an input artifact**: implementation branches from latest `main`; `plan.md` is copied into the worktree with a checksum. The plan's own PR is independent.
4. **Claude review runs on the host, outside Codex's sandbox** → Codex needs only `-s workspace-write`, no network, no `gh`. Removes the network-escalation risk.
5. **Session state = hybrid**: files are the source of truth; Codex is resumed by **explicit `thread_id`** for continuity/token savings, with fresh-call fallback if the session is gone.
6. **Termination**: max 3 review rounds (initial + 2 fixes); early-exit on `approve` / zero blocking findings / unchanged diff / repeated same-cause failure; on cap, open a **draft** PR documenting residuals.

## File Structure

```
.claude-plugin/marketplace.json          # MODIFY: add cx entry
cx/
  .claude-plugin/plugin.json             # plugin manifest
  README.md                              # user guide + flow diagram
  hooks.json                             # PreToolUse secret guard (reuse hv pattern)
  schemas/
    claude-review.v1.schema.json         # Claude review output contract
    codex-loop-result.v1.schema.json     # Codex final result contract
  scripts/
    lib.sh                               # shared helpers (logging, thread_id capture, json validate)
    validate-json.py                     # JSON Schema validation, fail-closed
    run-loop.sh                          # SINGLE human entrypoint: worktree -> rounds -> PR -> watch
    codex-round.sh                       # one Codex implement/fix round (sandboxed, schema-bound)
    claude-review.sh                     # host-side: claude -p /cx:review-diff -> validated JSON
    post-summary.sh                      # post Claude×Codex exchange summary as PR comment
    watch-clean.sh                       # poll PR; on merge remove worktree+branch
    spar-codex.sh                        # helper: send a prompt to codex exec, return its text
    guard-protected.sh                   # secret-file guard (copied/adapted from hv)
  agents-skills/
    implement-round/SKILL.md             # Codex skill: implement ONE round from plan + prior review
  skills/
    plan-loop/SKILL.md                   # /cx:plan-loop  — Claude drafts plan, spars with Codex, saves
    review-diff/SKILL.md                 # /cx:review-diff — Claude standalone diff review -> v1 JSON
    start/SKILL.md                       # /cx:start      — kicks off scripts/run-loop.sh
  shared/contracts/
    review-contract.md                   # human-readable spec of claude-review.v1
    loop-contract.md                     # human-readable spec of the loop + codex-loop-result.v1
  tests/                                 # bash tests per task + run-all.sh + e2e-smoke.md
```

---

## Task 1: Scaffold the plugin and register it in the marketplace

**Files:**
- Create: `cx/.claude-plugin/plugin.json`
- Modify: `.claude-plugin/marketplace.json`
- Test: `cx/scripts/validate-scaffold.sh` (temporary; deleted in step 5)

- [ ] **Step 1: Write a failing scaffold check**

`cx/scripts/validate-scaffold.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
test -f "$ROOT/cx/.claude-plugin/plugin.json" || { echo "FAIL: plugin.json missing"; exit 1; }
python3 -c "import json; d=json.load(open('$ROOT/cx/.claude-plugin/plugin.json')); assert d['name']=='cx', d"
python3 -c "import json; m=json.load(open('$ROOT/.claude-plugin/marketplace.json')); assert any(p.get('name')=='cx' for p in m.get('plugins',[])), 'cx not registered'"
echo "OK: scaffold valid"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash cx/scripts/validate-scaffold.sh` → Expected: FAIL with "plugin.json missing".

- [ ] **Step 3: Create the manifest and register it**

`cx/.claude-plugin/plugin.json`:

```json
{
  "name": "cx",
  "displayName": "Cx",
  "description": "Claude x Codex loop: plan -> implement (Codex, worktree-isolated) -> review (Claude) -> adjust -> PR -> cleanup.",
  "version": "0.1.0",
  "keywords": ["codex", "claude", "parallel", "worktree", "code-review", "orchestration", "cross-tool"]
}
```

Add to `.claude-plugin/marketplace.json` `plugins` array, matching the existing entry shape used by `pw`/`hv` (e.g. `{ "name": "cx", "source": "./cx" }`).

- [ ] **Step 4: Run the check and `claude plugin validate`**

Run: `bash cx/scripts/validate-scaffold.sh` → Expected: `OK: scaffold valid`.
Run: `claude plugin validate ./cx` → Expected: passes.

- [ ] **Step 5: Remove the temp check and commit**

```bash
rm cx/scripts/validate-scaffold.sh
git add cx/.claude-plugin/plugin.json .claude-plugin/marketplace.json
git commit -m "feat(cx): scaffold plugin and register in marketplace"
```

---

## Task 2: Define the handoff contracts (JSON schemas + docs)

**Files:**
- Create: `cx/schemas/claude-review.v1.schema.json`, `cx/schemas/codex-loop-result.v1.schema.json`
- Create: `cx/shared/contracts/review-contract.md`, `cx/shared/contracts/loop-contract.md`
- Create: `cx/scripts/validate-json.py`
- Test: `cx/tests/test_schemas.sh`

- [ ] **Step 1: Write the failing schema test**

`cx/tests/test_schemas.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
V="$ROOT/cx/scripts/validate-json.py"; S="$ROOT/cx/schemas"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/good.json" <<'JSON'
{"schema_version":"cx_claude_review.v1","round":1,"verdict":"request_changes",
 "summary":"x","findings":[{"id":"C001","blocking":true,"severity":"major",
 "file":"a.ts","line":1,"title":"t","evidence":"e","recommended_fix":"f"}],
 "verification":[{"claim":"builds","result":"pass","evidence":"ok"}]}
JSON
cat > "$TMP/bad.json" <<'JSON'
{"schema_version":"cx_claude_review.v1","verdict":"maybe"}
JSON
python3 "$V" "$S/claude-review.v1.schema.json" "$TMP/good.json" || { echo "FAIL: good rejected"; exit 1; }
if python3 "$V" "$S/claude-review.v1.schema.json" "$TMP/bad.json"; then echo "FAIL: bad accepted"; exit 1; fi
echo "OK: schema validation works"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash cx/tests/test_schemas.sh` → Expected: FAIL (validator + schemas absent).

- [ ] **Step 3: Write `validate-json.py` (stdlib-only, fail-closed)**

```python
#!/usr/bin/env python3
import json, sys

def fail(msg):
    print(f"schema violation: {msg}", file=sys.stderr); sys.exit(1)

def check(node, schema, path="$"):
    t = schema.get("type")
    if t == "object":
        if not isinstance(node, dict): fail(f"{path}: expected object")
        for r in schema.get("required", []):
            if r not in node: fail(f"{path}.{r}: required")
        props = schema.get("properties", {})
        if schema.get("additionalProperties") is False:
            for k in node:
                if k not in props: fail(f"{path}.{k}: additional property not allowed")
        for k, sub in props.items():
            if k in node: check(node[k], sub, f"{path}.{k}")
    elif t == "array":
        if not isinstance(node, list): fail(f"{path}: expected array")
        item = schema.get("items")
        if item:
            for i, el in enumerate(node): check(el, item, f"{path}[{i}]")
    elif t == "string":
        if not isinstance(node, str): fail(f"{path}: expected string")
    elif t == "integer":
        if not isinstance(node, int) or isinstance(node, bool): fail(f"{path}: expected integer")
    elif t == "boolean":
        if not isinstance(node, bool): fail(f"{path}: expected boolean")
    if "enum" in schema and node not in schema["enum"]:
        fail(f"{path}: {node!r} not in {schema['enum']}")

def main():
    if len(sys.argv) != 3:
        print("usage: validate-json.py <schema.json> <doc.json>", file=sys.stderr); sys.exit(2)
    try:
        schema = json.load(open(sys.argv[1])); doc = json.load(open(sys.argv[2]))
    except Exception as e:
        print(f"parse error: {e}", file=sys.stderr); sys.exit(2)
    check(doc, schema); sys.exit(0)

if __name__ == "__main__":
    main()
```

- [ ] **Step 4: Write the two schemas**

`cx/schemas/claude-review.v1.schema.json`:

```json
{
  "type": "object",
  "additionalProperties": false,
  "required": ["schema_version", "round", "verdict", "summary", "findings"],
  "properties": {
    "schema_version": { "type": "string", "enum": ["cx_claude_review.v1"] },
    "round": { "type": "integer" },
    "verdict": { "type": "string", "enum": ["approve", "request_changes", "blocked"] },
    "summary": { "type": "string" },
    "findings": {
      "type": "array",
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["id", "blocking", "severity", "title"],
        "properties": {
          "id": { "type": "string" },
          "blocking": { "type": "boolean" },
          "severity": { "type": "string", "enum": ["blocker", "major", "minor"] },
          "file": { "type": "string" },
          "line": { "type": "integer" },
          "title": { "type": "string" },
          "evidence": { "type": "string" },
          "recommended_fix": { "type": "string" }
        }
      }
    },
    "verification": {
      "type": "array",
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["claim", "result"],
        "properties": {
          "claim": { "type": "string" },
          "result": { "type": "string", "enum": ["pass", "fail", "unknown"] },
          "evidence": { "type": "string" }
        }
      }
    }
  }
}
```

`cx/schemas/codex-loop-result.v1.schema.json`:

```json
{
  "type": "object",
  "additionalProperties": false,
  "required": ["schema_version", "status", "round"],
  "properties": {
    "schema_version": { "type": "string", "enum": ["cx_codex_loop_result.v1"] },
    "status": { "type": "string", "enum": ["in_progress", "converged", "draft_with_residuals", "blocked", "failed"] },
    "round": { "type": "integer" },
    "head_sha": { "type": "string" },
    "addressed": { "type": "array", "items": { "type": "string" } },
    "disputed_findings": {
      "type": "array",
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["id", "reason"],
        "properties": { "id": { "type": "string" }, "reason": { "type": "string" } }
      }
    },
    "notes": { "type": "string" }
  }
}
```

- [ ] **Step 5: Write the contract docs**

`cx/shared/contracts/review-contract.md` and `loop-contract.md` describe, in prose, each field above, the enums, the fail-closed rule (unknown/malformed → driver treats as `blocked`), and how `blocking:true` findings gate progression. These are the single source of truth referenced by both skills (DRY — skills link here, don't restate fields).

- [ ] **Step 6: Run the test and commit**

Run: `bash cx/tests/test_schemas.sh` → Expected: `OK: schema validation works`.
Run: `python3 -m py_compile cx/scripts/validate-json.py` → Expected: no output.

```bash
git add cx/schemas cx/shared/contracts cx/scripts/validate-json.py cx/tests/test_schemas.sh
git commit -m "feat(cx): define claude-review.v1 and codex-loop-result.v1 contracts"
```

---

## Task 3: `lib.sh` — shared helpers (thread_id capture, logging, validation)

**Files:**
- Create: `cx/scripts/lib.sh`
- Test: `cx/tests/test_lib.sh`

- [ ] **Step 1: Write the failing test**

`cx/tests/test_lib.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
source "$ROOT/cx/scripts/lib.sh"
printf '%s\n' '{"type":"thread.started","thread_id":"abc-123"}' '{"type":"turn.completed"}' > /tmp/cx_test.jsonl
got="$(extract_thread_id /tmp/cx_test.jsonl)"
[ "$got" = "abc-123" ] || { echo "FAIL: got '$got'"; exit 1; }
echo "OK: lib helpers work"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash cx/tests/test_lib.sh` → Expected: FAIL ("No such file" — lib.sh missing).

- [ ] **Step 3: Implement `lib.sh`**

```bash
#!/usr/bin/env bash
# cx shared helpers. Source me; do not execute.
CODEX_BIN="${CODEX_BIN:-codex}"   # override if codex is off PATH (e.g. a mise shim)

cx_log()  { printf '[cx] %s\n' "$*" >&2; }
cx_die()  { printf '[cx] ERROR: %s\n' "$*" >&2; exit 1; }

# Read a codex `--json` JSONL file, print the thread_id from the thread.started event.
extract_thread_id() {
  python3 - "$1" <<'PY'
import json, sys
for line in open(sys.argv[1]):
    line = line.strip()
    if not line: continue
    try: o = json.loads(line)
    except Exception: continue
    if o.get("type") == "thread.started" and o.get("thread_id"):
        print(o["thread_id"]); break
PY
}

# Validate a JSON doc against a schema; on failure print stderr and return 1 (fail-closed).
cx_validate() {  # cx_validate <schema> <doc>
  python3 "$(dirname "${BASH_SOURCE[0]}")/validate-json.py" "$1" "$2"
}
```

- [ ] **Step 4: Run the test and commit**

Run: `bash cx/tests/test_lib.sh` → Expected: `OK: lib helpers work`.
Run: `bash -n cx/scripts/lib.sh` → Expected: no output.

```bash
git add cx/scripts/lib.sh cx/tests/test_lib.sh
git commit -m "feat(cx): add lib.sh shared helpers (thread_id capture, validation)"
```

---

## Task 4: Codex skill — implement ONE round

**Files:**
- Create: `cx/agents-skills/implement-round/SKILL.md`
- Test: `cx/tests/test_codex_skill_frontmatter.sh`

- [ ] **Step 1: Write the failing frontmatter test**

`cx/tests/test_codex_skill_frontmatter.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
F="$ROOT/cx/agents-skills/implement-round/SKILL.md"
test -f "$F" || { echo "FAIL: SKILL.md missing"; exit 1; }
head -1 "$F" | grep -q '^---$' || { echo "FAIL: no frontmatter"; exit 1; }
grep -q '^name: implement-round$' "$F" || { echo "FAIL: name must equal dir"; exit 1; }
grep -q '^description:' "$F" || { echo "FAIL: description required"; exit 1; }
echo "OK: codex skill frontmatter valid"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash cx/tests/test_codex_skill_frontmatter.sh` → Expected: FAIL ("SKILL.md missing").

- [ ] **Step 3: Write the Codex skill**

`cx/agents-skills/implement-round/SKILL.md` — frontmatter `name: implement-round`, `description:` explaining it implements/fixes ONE round. Body instructs Codex to:
1. Read inputs (absolute paths passed in the prompt): `plan.md`, the previous `review-round-N.json` (absent on round 1), and the worktree itself.
2. Round 1: implement the plan test-first within the worktree only; do not touch files outside it; do not run `git push` or `gh`.
3. Round N>1: address every `blocking:true` finding from the review JSON; for findings you believe are wrong, do NOT silently skip — record them in `disputed_findings` with a reason.
4. Run the repo's tests/lint/build and leave evidence on disk.
5. Emit a `cx_codex_loop_result.v1` JSON object as the final message (the driver binds it with `--output-schema`).
6. Hard rules: stay inside the worktree; no network; never edit `.env`/secrets; keep the diff scoped to the plan.

Link `shared/contracts/loop-contract.md` for the result schema (DRY).

- [ ] **Step 4: Run the test and commit**

Run: `bash cx/tests/test_codex_skill_frontmatter.sh` → Expected: `OK`.

```bash
git add cx/agents-skills/implement-round/SKILL.md cx/tests/test_codex_skill_frontmatter.sh
git commit -m "feat(cx): add Codex implement-round skill"
```

---

## Task 5: `codex-round.sh` — wrap one Codex round (sandboxed, schema-bound, thread-safe)

**Files:**
- Create: `cx/scripts/codex-round.sh`
- Test: `cx/tests/test_codex_round_dryrun.sh` (uses a stub `codex`)

- [ ] **Step 1: Write the failing dry-run test (stubbed codex)**

`cx/tests/test_codex_round_dryrun.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/codex" <<'STUB'
#!/usr/bin/env bash
out=""; while [ $# -gt 0 ]; do case "$1" in -o) out="$2"; shift 2;; *) shift;; esac; done
echo '{"type":"thread.started","thread_id":"t-1"}'
[ -n "$out" ] && printf '%s' '{"schema_version":"cx_codex_loop_result.v1","status":"in_progress","round":1}' > "$out"
exit 0
STUB
chmod +x "$TMP/codex"
export CODEX_BIN="$TMP/codex"
WT="$TMP/wt"; mkdir -p "$WT"; RUN="$TMP/run"; mkdir -p "$RUN"; echo "# plan" > "$RUN/plan.md"
bash "$ROOT/cx/scripts/codex-round.sh" --worktree "$WT" --run "$RUN" --round 1 \
  && echo "OK: codex-round dry run passed" || { echo "FAIL"; exit 1; }
[ -f "$RUN/thread_id" ] && [ "$(cat "$RUN/thread_id")" = "t-1" ] || { echo "FAIL: thread_id not captured"; exit 1; }
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash cx/tests/test_codex_round_dryrun.sh` → Expected: FAIL ("codex-round.sh: No such file").

- [ ] **Step 3: Implement `codex-round.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; source "$HERE/lib.sh"
ROOT="$(git rev-parse --show-toplevel)"

WT="" RUN="" ROUND="" SID=""
while [ $# -gt 0 ]; do case "$1" in
  --worktree) WT="$2"; shift 2;; --run) RUN="$2"; shift 2;;
  --round) ROUND="$2"; shift 2;; --thread-id) SID="$2"; shift 2;;
  *) cx_die "unknown arg: $1";; esac; done
[ -n "$WT$RUN$ROUND" ] || cx_die "usage: --worktree --run --round [--thread-id]"

SKILL="$ROOT/cx/agents-skills/implement-round/SKILL.md"
SCHEMA="$ROOT/cx/schemas/codex-loop-result.v1.schema.json"
OUT="$RUN/codex-result-$ROUND.json"; JSONL="$RUN/codex-$ROUND.jsonl"
PREV_REVIEW="$RUN/review-round-$((ROUND-1)).json"
prev_clause=""; [ -f "$PREV_REVIEW" ] && prev_clause="Previous review JSON: $PREV_REVIEW"

PROMPT="Read and follow this skill EXACTLY as the controlling procedure: $SKILL

Plan: $RUN/plan.md
$prev_clause
Round: $ROUND
Work only inside this worktree. No network. No git push, no gh.
Emit the final cx_codex_loop_result.v1 JSON."

common=( -C "$WT" -s workspace-write -c approval_policy=never
         --output-schema "$SCHEMA" -o "$OUT" --json )
if [ -n "$SID" ]; then
  "$CODEX_BIN" exec resume "$SID" "${common[@]}" "$PROMPT" >"$JSONL" 2>>"$RUN/codex-$ROUND.stderr" || true
else
  "$CODEX_BIN" exec "${common[@]}" "$PROMPT" >"$JSONL" 2>>"$RUN/codex-$ROUND.stderr" || true
fi

[ -f "$OUT" ] || cx_die "codex produced no result file"
cx_validate "$SCHEMA" "$OUT" || cx_die "codex result failed schema validation (fail-closed)"
TID="$(extract_thread_id "$JSONL" || true)"
[ -n "$TID" ] && printf '%s' "$TID" > "$RUN/thread_id"
cx_log "round $ROUND implemented; result=$OUT thread_id=${TID:-none}"
```

- [ ] **Step 4: Run the test and commit**

Run: `bash cx/tests/test_codex_round_dryrun.sh` → Expected: `OK: codex-round dry run passed`.
Run: `bash -n cx/scripts/codex-round.sh` → Expected: no output.

```bash
git add cx/scripts/codex-round.sh cx/tests/test_codex_round_dryrun.sh
git commit -m "feat(cx): codex-round.sh runs one sandboxed schema-bound Codex round"
```

---

## Task 6: Claude review skill + host-side review script

**Files:**
- Create: `cx/skills/review-diff/SKILL.md`
- Create: `cx/scripts/claude-review.sh`
- Test: `cx/tests/test_claude_review_dryrun.sh` (stub `claude`)

- [ ] **Step 1: Write the failing dry-run test (stubbed claude)**

`cx/tests/test_claude_review_dryrun.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/claude" <<'STUB'
#!/usr/bin/env bash
cat > "$CX_OUT" <<'J'
{"schema_version":"cx_claude_review.v1","round":1,"verdict":"approve","summary":"ok","findings":[]}
J
STUB
chmod +x "$TMP/claude"
export CLAUDE_BIN="$TMP/claude"
RUN="$TMP/run"; mkdir -p "$RUN"; echo "diff" > "$RUN/round-1.diff"; echo "# plan" > "$RUN/plan.md"
verdict="$(bash "$ROOT/cx/scripts/claude-review.sh" --run "$RUN" --round 1 --worktree "$TMP")"
[ "$verdict" = "approve" ] || { echo "FAIL: verdict=$verdict"; exit 1; }
echo "OK: claude-review dry run passed"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash cx/tests/test_claude_review_dryrun.sh` → Expected: FAIL ("claude-review.sh: No such file").

- [ ] **Step 3: Write the `/cx:review-diff` skill**

`cx/skills/review-diff/SKILL.md` — frontmatter:

```yaml
---
name: review-diff
description: Review a worktree diff against its plan for correctness, security, and codebase consistency, emitting a cx_claude_review.v1 JSON verdict. Used by the cx loop before a PR exists.
model: opus
effort: high
allowed-tools: Read, Grep, Glob, Bash, WebFetch
disable-model-invocation: true
---
```

Body: read the plan, the diff, and surrounding code; apply the review *criteria* ported from `hv/skills/review-pr/SKILL.md` (correctness, security, consistency, evidence-based, adversarial where risky); web search when a claim needs external grounding; output the `cx_claude_review.v1` object (link `shared/contracts/review-contract.md` for fields). Mark a finding `blocking:true` only for must-fix issues. The skill writes the JSON to the path given in the invocation (`$CX_OUT`).

- [ ] **Step 4: Implement `claude-review.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; source "$HERE/lib.sh"
ROOT="$(git rev-parse --show-toplevel)"
CLAUDE_BIN="${CLAUDE_BIN:-claude}"

RUN="" ROUND="" WT=""
while [ $# -gt 0 ]; do case "$1" in
  --run) RUN="$2"; shift 2;; --round) ROUND="$2"; shift 2;;
  --worktree) WT="$2"; shift 2;; *) cx_die "unknown arg: $1";; esac; done
[ -n "$RUN$ROUND$WT" ] || cx_die "usage: --run --round --worktree"

SCHEMA="$ROOT/cx/schemas/claude-review.v1.schema.json"
OUT="$RUN/review-round-$ROUND.json"; export CX_OUT="$OUT"

PROMPT="/cx:review-diff
plan=$RUN/plan.md
diff=$RUN/round-$ROUND.diff
worktree=$WT
round=$ROUND
Write the cx_claude_review.v1 JSON to: $OUT"

# Host-side; Claude has network/web-search. Runs OUTSIDE the Codex sandbox.
"$CLAUDE_BIN" -p "$PROMPT" >/dev/null 2>>"$RUN/claude-$ROUND.stderr" || true

[ -f "$OUT" ] || cx_die "claude produced no review file"
cx_validate "$SCHEMA" "$OUT" || cx_die "review failed schema validation (fail-closed -> treat as blocked)"
python3 -c "import json;print(json.load(open('$OUT'))['verdict'])"
```

- [ ] **Step 5: Run the test and commit**

Run: `bash cx/tests/test_claude_review_dryrun.sh` → Expected: `OK: claude-review dry run passed`.
Run: `bash -n cx/scripts/claude-review.sh` → Expected: no output.

```bash
git add cx/skills/review-diff cx/scripts/claude-review.sh cx/tests/test_claude_review_dryrun.sh
git commit -m "feat(cx): /cx:review-diff skill + host-side claude-review.sh"
```

---

## Task 7: `run-loop.sh` — the single entrypoint (worktree → rounds → PR)

**Files:**
- Create: `cx/scripts/run-loop.sh`
- Test: `cx/tests/test_run_loop_convergence.sh` (stubs codex + claude + gh)

- [ ] **Step 1: Write the failing convergence test**

`cx/tests/test_run_loop_convergence.sh` stubs `codex` (writes loop-result + thread.started), `claude` (round 1 → `request_changes` with one blocking finding, round 2 → `approve`), and `gh` (records `pr create`). Asserts exactly 2 review rounds, then `gh pr create`, and `status: converged`.

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/bin"; mkdir -p "$BIN"
cat > "$BIN/codex" <<'S'
#!/usr/bin/env bash
out=""; while [ $# -gt 0 ]; do case "$1" in -o) out="$2"; shift 2;; *) shift;; esac; done
echo '{"type":"thread.started","thread_id":"t-1"}'
[ -n "$out" ] && printf '%s' '{"schema_version":"cx_codex_loop_result.v1","status":"in_progress","round":1}' > "$out"
S
cat > "$BIN/claude" <<S
#!/usr/bin/env bash
n="$TMP/n"; c=\$(( \$(cat "\$n" 2>/dev/null || echo 0) + 1 )); echo "\$c" > "\$n"
if [ "\$c" -ge 2 ]; then v=approve; f='[]'; else v=request_changes; f='[{"id":"C1","blocking":true,"severity":"major","title":"fix"}]'; fi
printf '{"schema_version":"cx_claude_review.v1","round":%s,"verdict":"%s","summary":"s","findings":%s}' "\$c" "\$v" "\$f" > "\$CX_OUT"
S
cat > "$BIN/gh" <<'S'
#!/usr/bin/env bash
echo "gh $*" >> "$TMP/gh.log"; echo "https://example/pr/1"
S
sed -i '' "s#\$TMP#$TMP#g" "$BIN/gh" 2>/dev/null || sed -i "s#\$TMP#$TMP#g" "$BIN/gh"
chmod +x "$BIN"/*
export PATH="$BIN:$PATH" CODEX_BIN="$BIN/codex" CLAUDE_BIN="$BIN/claude"
echo "# plan" > "$TMP/plan.md"
out="$(bash "$ROOT/cx/scripts/run-loop.sh" "$TMP/plan.md" --no-worktree --base HEAD --max-rounds 3 2>&1 || true)"
echo "$out" | grep -q "converged" || { echo "FAIL: not converged: $out"; exit 1; }
grep -q "pr create" "$TMP/gh.log" || { echo "FAIL: no PR created"; exit 1; }
echo "OK: run-loop converges and opens PR"
```

(`--no-worktree` runs the loop in place for testing; production omits it.)

- [ ] **Step 2: Run it to verify it fails**

Run: `bash cx/tests/test_run_loop_convergence.sh` → Expected: FAIL ("run-loop.sh: No such file").

- [ ] **Step 3: Implement `run-loop.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; source "$HERE/lib.sh"
ROOT="$(git rev-parse --show-toplevel)"

PLAN="${1:?usage: run-loop.sh <plan.md> [--base main] [--max-rounds 3] [--no-worktree]}"; shift || true
BASE="main" MAXR=3 USE_WT=1
while [ $# -gt 0 ]; do case "$1" in
  --base) BASE="$2"; shift 2;; --max-rounds) MAXR="$2"; shift 2;;
  --no-worktree) USE_WT=0; shift;; *) cx_die "unknown arg: $1";; esac; done
[ -f "$PLAN" ] || cx_die "plan not found: $PLAN"

ID="$(basename "$PLAN" .md)"
RUN="$ROOT/.cx/runs/$ID"; mkdir -p "$RUN"
cp "$PLAN" "$RUN/plan.md"
shasum -a 256 "$PLAN" | awk '{print $1}' > "$RUN/plan.sha256"

if [ "$USE_WT" = 1 ]; then
  git -C "$ROOT" fetch origin "$BASE"
  WT="$ROOT/../.cx-worktrees/$(basename "$ROOT")/$ID"; BR="cx/$ID"
  git -C "$ROOT" worktree add -b "$BR" "$WT" "origin/$BASE"
else
  WT="$ROOT"; BR="$(git -C "$ROOT" rev-parse --abbrev-ref HEAD)"
fi
cx_log "worktree=$WT branch=$BR"

SID=""; [ -f "$RUN/thread_id" ] && SID="$(cat "$RUN/thread_id")"
round=1 verdict="" prev_diff=""
while [ "$round" -le "$MAXR" ]; do
  cx_log "=== round $round: implement ==="
  bash "$HERE/codex-round.sh" --worktree "$WT" --run "$RUN" --round "$round" ${SID:+--thread-id "$SID"}
  [ -f "$RUN/thread_id" ] && SID="$(cat "$RUN/thread_id")"

  git -C "$WT" add -A
  git -C "$WT" diff --cached "origin/$BASE"...HEAD > "$RUN/round-$round.diff" 2>/dev/null \
    || git -C "$WT" diff --cached > "$RUN/round-$round.diff"

  if [ -n "$prev_diff" ] && cmp -s "$prev_diff" "$RUN/round-$round.diff"; then
    cx_log "diff unchanged -> stop"; verdict="stalled"; break
  fi
  prev_diff="$RUN/round-$round.diff"

  cx_log "=== round $round: review ==="
  verdict="$(bash "$HERE/claude-review.sh" --run "$RUN" --round "$round" --worktree "$WT")"
  cx_log "verdict=$verdict"
  blocking="$(python3 -c "import json;d=json.load(open('$RUN/review-round-$round.json'));print(sum(1 for f in d['findings'] if f.get('blocking')))")"
  if [ "$verdict" = "approve" ] || [ "$blocking" = 0 ]; then verdict="approve"; break; fi
  round=$((round+1))
done

git -C "$WT" add -A
git -C "$WT" commit -m "feat: implement $ID (cx loop)" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>" || true
DRAFT=""; STATUS="converged"
if [ "$verdict" != "approve" ]; then DRAFT="--draft"; STATUS="draft_with_residuals"; fi
[ "$USE_WT" = 1 ] && git -C "$WT" push -u origin "$BR"
PR_URL="$(cd "$WT" && gh pr create --base "$BASE" --head "$BR" $DRAFT \
  --title "feat: $ID" --body-file "$RUN/plan.md" 2>/dev/null || echo "")"
bash "$HERE/post-summary.sh" "$RUN" "$PR_URL" 2>/dev/null || true
cx_log "status: $STATUS pr=$PR_URL"
echo "status: $STATUS"

[ "$USE_WT" = 1 ] && [ -n "$PR_URL" ] && \
  nohup bash "$HERE/watch-clean.sh" --pr "$PR_URL" --worktree "$WT" --branch "$BR" >/dev/null 2>&1 &
```

- [ ] **Step 4: Run the test and commit**

Run: `bash cx/tests/test_run_loop_convergence.sh` → Expected: `OK: run-loop converges and opens PR`.
Run: `bash -n cx/scripts/run-loop.sh` → Expected: no output.

```bash
git add cx/scripts/run-loop.sh cx/tests/test_run_loop_convergence.sh
git commit -m "feat(cx): run-loop.sh drives worktree -> rounds -> PR"
```

---

## Task 8: Exchange summary + watch-and-clean

**Files:**
- Create: `cx/scripts/post-summary.sh`, `cx/scripts/watch-clean.sh`
- Test: `cx/tests/test_summary.sh`, `cx/tests/test_watch_clean.sh`

- [ ] **Step 1: Write the failing summary test**

`cx/tests/test_summary.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/bin"; mkdir -p "$BIN"
cat > "$BIN/gh" <<'S'
#!/usr/bin/env bash
echo "gh $*" >> "$GH_LOG"
S
chmod +x "$BIN/gh"; export PATH="$BIN:$PATH" GH_LOG="$TMP/gh.log"
RUN="$TMP/run"; mkdir -p "$RUN"
echo '{"schema_version":"cx_claude_review.v1","round":1,"verdict":"approve","summary":"looks good","findings":[]}' > "$RUN/review-round-1.json"
bash "$ROOT/cx/scripts/post-summary.sh" "$RUN" "https://example/pr/1"
grep -q "pr comment" "$GH_LOG" || { echo "FAIL: no comment posted"; exit 1; }
echo "OK: summary posted"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash cx/tests/test_summary.sh` → Expected: FAIL ("post-summary.sh: No such file").

- [ ] **Step 3: Implement `post-summary.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
RUN="${1:?run dir}"; PR="${2:-}"
[ -n "$PR" ] || { echo "[cx] no PR url; skipping summary"; exit 0; }
MD="$RUN/exchange-summary.md"
{
  echo "## cx loop — Claude×Codex exchange summary"; echo
  for r in "$RUN"/review-round-*.json; do
    [ -f "$r" ] || continue
    n="$(basename "$r" | sed 's/[^0-9]//g')"
    python3 - "$r" "$n" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); n=sys.argv[2]
print(f"### Round {n} — Claude verdict: **{d['verdict']}**")
print(f"> {d.get('summary','').strip()}")
for f in d.get('findings',[]):
    flag="🚫 blocking" if f.get('blocking') else "note"
    print(f"- [{flag}] **{f.get('title','')}** ({f.get('severity','')}) `{f.get('file','')}`")
print()
PY
  done
  echo "_Generated by the cx loop._"
} > "$MD"
gh pr comment "$PR" --body-file "$MD"
```

- [ ] **Step 4: Implement `watch-clean.sh` (adapt `hv/scripts/watch-merge.sh`)**

Poll the PR with exponential backoff (initial 30s, ×2, cap 600s, give up after 24h). On `MERGED`: `git -C "$ROOT" worktree remove "<worktree>"` (no `--force`) then `git -C "$ROOT" branch -d "<branch>"` and `git -C "$ROOT" worktree prune`. On `CLOSED_UNMERGED`: clean nothing, report. Reuse the safety posture from `hv/agents/janitor.md` (never remove a worktree with uncommitted changes; `-d` not `-D`).

- [ ] **Step 5: Write `test_watch_clean.sh`**

Stub `gh pr view` to report a merged PR immediately; create a real throwaway worktree inside a temp git repo; assert `watch-clean.sh` removes it and deletes the branch. Never touches the real repo.

- [ ] **Step 6: Run tests and commit**

Run: `bash cx/tests/test_summary.sh` → Expected: `OK: summary posted`.
Run: `bash cx/tests/test_watch_clean.sh` → Expected: OK.
Run: `bash -n cx/scripts/post-summary.sh cx/scripts/watch-clean.sh` → Expected: no output.

```bash
git add cx/scripts/post-summary.sh cx/scripts/watch-clean.sh cx/tests/test_summary.sh cx/tests/test_watch_clean.sh
git commit -m "feat(cx): post exchange summary + watch-and-clean on merge"
```

---

## Task 9: Claude planning skill (`/cx:plan-loop`) + `/cx:start`

**Files:**
- Create: `cx/skills/plan-loop/SKILL.md`, `cx/skills/start/SKILL.md`, `cx/scripts/spar-codex.sh`
- Test: `cx/tests/test_skill_identity.sh`

- [ ] **Step 1: Write the failing identity test**

`cx/tests/test_skill_identity.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"; fail=0
for f in "$ROOT"/cx/skills/*/SKILL.md; do
  d="$(basename "$(dirname "$f")")"
  grep -q "^name: $d$" "$f" || { echo "FAIL: $f name != $d"; fail=1; }
  grep -q "^description:" "$f" || { echo "FAIL: $f no description"; fail=1; }
done
[ "$fail" = 0 ] && echo "OK: skill identities valid"; exit "$fail"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash cx/tests/test_skill_identity.sh` → Expected: FAIL (plan-loop / start absent).

- [ ] **Step 3: Write `spar-codex.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; source "$HERE/lib.sh"
PROMPT_FILE="${1:?prompt file}"
"$CODEX_BIN" exec --sandbox read-only -c model_reasoning_effort=high - < "$PROMPT_FILE" 2>/dev/null
```

- [ ] **Step 4: Write the skills**

`cx/skills/plan-loop/SKILL.md` (`name: plan-loop`, `model: opus`, `effort: xhigh`, `allowed-tools: Read, Grep, Glob, Bash, WebFetch, Agent`): Claude brainstorms/drafts an implementation plan, **spars with Codex via `scripts/spar-codex.sh`** across 1–2 rounds (feeding Codex the running draft, incorporating its critique), finalizes, and saves to `docs/superpowers/plans/YYYY-MM-DD-<name>.md`. Optionally opens a plan PR if asked.

`cx/skills/start/SKILL.md` (`name: start`, `disable-model-invocation: true`, `allowed-tools: Read, Bash`): given a saved plan path, runs `scripts/run-loop.sh <plan>` and reports the resulting PR. One-command kickoff.

- [ ] **Step 5: Run the test, validate, commit**

Run: `bash cx/tests/test_skill_identity.sh` → Expected: `OK: skill identities valid`.
Run: `claude plugin validate ./cx` → Expected: passes.

```bash
git add cx/skills/plan-loop cx/skills/start cx/scripts/spar-codex.sh cx/tests/test_skill_identity.sh
git commit -m "feat(cx): /cx:plan-loop (spar with Codex) and /cx:start kickoff"
```

---

## Task 10: Secret guard, README, full validation

**Files:**
- Create: `cx/hooks.json`, `cx/scripts/guard-protected.sh`, `cx/README.md`, `cx/tests/run-all.sh`, `cx/tests/test_guard.sh`

- [ ] **Step 1: Copy and verify the secret guard**

Reuse `hv/scripts/guard-protected.sh` verbatim (do not weaken it) and a `cx/hooks.json` wiring it to `PreToolUse` on `Edit|Write|NotebookEdit`. `cx/tests/test_guard.sh` pipes a `.env` Edit payload → assert exit 2 (blocked); a normal file payload → assert exit 0.

- [ ] **Step 2: Write `cx/README.md`**

Document: install; the one-command flow (`/cx:plan-loop` → saved plan → `/cx:start <plan>` or `scripts/run-loop.sh <plan>`); the loop diagram; the contracts (link `shared/contracts/`); the session-state model (explicit `thread_id`, never `--last`); the sandbox posture (Codex `workspace-write`/no-net; Claude review on host); `CODEX_BIN`/`CLAUDE_BIN` overrides for off-PATH binaries.

- [ ] **Step 3: Write `cx/tests/run-all.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
for t in "$ROOT"/cx/tests/test_*.sh; do echo "== $t =="; bash "$t"; done
echo "ALL CX TESTS PASSED"
```

- [ ] **Step 4: Full validation gate**

Run: `bash cx/tests/run-all.sh` → Expected: `ALL CX TESTS PASSED`.
Run: `bash -n cx/scripts/*.sh` → Expected: no output.
Run: `python3 -m py_compile cx/scripts/validate-json.py` → Expected: no output.
Run: `claude plugin validate ./cx` and `claude plugin validate ./hv` → Expected: both pass.

- [ ] **Step 5: Commit**

```bash
git add cx/hooks.json cx/scripts/guard-protected.sh cx/README.md cx/tests/run-all.sh cx/tests/test_guard.sh
git commit -m "feat(cx): secret guard, README, full test gate"
```

---

## Task 11: End-to-end smoke test on a throwaway repo (manual)

**Files:**
- Create: `cx/tests/e2e-smoke.md` (manual runbook)

- [ ] **Step 1: Write the runbook**

Create a tiny throwaway git repo with a trivial feature request; write a 1-task plan; run `scripts/run-loop.sh plan.md` with **real** `codex` and `claude`; confirm: worktree under `.cx-worktrees/`, Codex implemented inside it (no network), Claude review JSON validated, ≤3 rounds, a (draft or ready) PR with an exchange-summary comment; simulate merge and confirm `watch-clean.sh` removes the worktree and branch. Record actual outputs.

- [ ] **Step 2: Run the smoke test and capture evidence**

Execute the runbook end-to-end once; paste real terminal output into the PR description. Acceptance proof that the cross-tool loop is seamless.

---

## Self-Review (run against the spec)

**Spec coverage** — ① plan + spar with Codex + save + PR → Task 9 (`/cx:plan-loop`, `spar-codex.sh`) + Task 1; ② Codex implements in isolated worktree referencing the plan → Tasks 4–5, worktree in Task 7; ③ Codex self-review then call Claude → loop in Task 7 calls `claude-review.sh` (Task 6); ④ Claude reviews plan+code+other code+web search → Task 6 skill (`WebFetch`/criteria from hv:review-pr); ⑤ Codex applies feedback → Task 4 round N>1 + Task 7 loop; ⑥ few rounds → PR + exchange summary comment → Task 7 + Task 8 (`post-summary.sh`); ⑦ human merges → worktree deleted → Task 8 (`watch-clean.sh`). All seven covered.

**Placeholder scan** — schemas, scripts, and skill frontmatter are concrete; skill *bodies* are specified by responsibility + linked contracts (intentional: prose skills, matching the hv pattern).

**Type/identifier consistency** — schema_version strings (`cx_claude_review.v1`, `cx_codex_loop_result.v1`); file names (`review-round-N.json`, `codex-result-N.json`, `round-N.diff`, `thread_id`); env overrides (`CODEX_BIN`, `CLAUDE_BIN`, `CX_OUT`); flags (`--worktree`, `--run`, `--round`, `--thread-id`, `--base`, `--max-rounds`, `--no-worktree`) used consistently across Tasks 2–10.

## Open risks to validate during implementation (not blockers)

- **R1 (deterministic skill firing):** Task 11 must confirm `codex exec` reliably follows the absolute-path skill instruction; else inline the skill body into the prompt.
- **Diff base in a fresh worktree:** `git diff origin/$BASE...HEAD` before the first commit — the loop stages with `git add -A` then diffs the index; Task 7 step must verify a non-empty diff on round 1.
- **`--output-schema` + `resume`:** confirm schema binding still applies on `resume` calls; else validate-and-retry in `codex-round.sh`.
- **`gh pr create --body-file plan.md`:** ensure the plan-as-input vs plan-as-PR-body distinction is clear in the PR (link the plan's own PR if it exists).
