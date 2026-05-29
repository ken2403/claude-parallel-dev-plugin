---
name: code-quality
description: Code quality standards for implementing and reviewing code. Use this whenever you write or change code, review a PR or diff, or someone asks to "review code", "check quality", "improve", or "refactor". Auto-activates during /hive:worker implementation and /hive:review so that quality is judged the same way it was built. Covers readability, naming, error handling, dead code, abstraction, tests, and matching existing style.
allowed-tools: Read, Grep, Glob, Bash
---

# Code Quality

Good code is code the next person can read, change, and trust. In hive, correctness is guaranteed by adversarial verification, not by hoping the author was careful — so quality is about everything verification does not catch: clarity, maintainability, and fitting the code that already exists. Apply this both when implementing (so the diff is right the first time) and when reviewing (so it is judged honestly).

## Ground yourself in the existing code first

Before judging or writing anything, learn how this repo already does it. The codebase's own conventions outrank generic best practices — a "better" pattern that nothing else uses is itself an inconsistency.

- `Glob` for sibling files of the same kind (`**/*Service.ts`, `**/handlers/*.py`) to see the established shape.
- `Grep` for how a function, type, or error is used elsewhere before you assume how it should be used here.
- `Read` a couple of representative files to absorb the error-handling style, naming, and module layout.

If you are deliberately deviating from an existing pattern, that is allowed — but the deviation must be explicit (a comment or PR note saying why), never silent. Silent deviation reads as a mistake to every future reader.

## What to evaluate

### Readability and structure
- Can you understand each function without scrolling back and forth? If not, it is doing too much.
- Deep nesting hides the happy path. Flatten with early returns / guard clauses.
- Long functions mixing levels of abstraction (parsing + business logic + I/O) should be split so each does one thing.
- Magic numbers and bare strings should be named constants when their meaning is not obvious from context.

### Naming
- Names describe intent, not type or implementation (`activeUsers`, not `list2`). A reader should predict what a thing does from its name.
- Match the repo's casing and vocabulary. If the codebase says `fetch`, do not introduce `get`/`load`/`retrieve` for the same idea — inconsistent synonyms make the code seem like it has distinctions it does not.

### Error handling
- Follow the codebase's existing strategy (exceptions vs. result types vs. error returns). Mixing strategies forces every caller to handle two worlds.
- Handle the failure cases that can actually happen here; do not swallow errors silently or catch-and-ignore. An empty `catch` is a future debugging session.
- Error messages should give the reader enough to act (what failed, with what input).

### Abstraction — appropriate, not premature
- Reuse an existing helper instead of re-implementing it. Duplicated logic drifts apart over time.
- But do not invent a framework for one caller. The right abstraction is the one the current requirements justify, not a speculative one.

### Dead and leftover code
- No unused functions, variables, imports, or commented-out blocks. Version control already remembers the old code; leaving it in the file only confuses.
- No debug prints / leftover scaffolding from the implementation session.

### Tests
- New behavior has tests; changed behavior has updated tests. The hive contract is that verification can confirm the claim — untested behavior cannot be confirmed.
- Tests cover the edge cases the code handles (empty, boundary, error paths), and follow the repo's existing test structure and naming.

## Common code smells

| Smell | Why it hurts | Fix |
|-------|--------------|-----|
| Long method | Hard to read, test, reuse | Extract smaller functions |
| Deep nesting | Obscures the main path | Early returns / guard clauses |
| N+1 query | Silent performance cliff | Eager-load / batch |
| God object | Change ripples everywhere | Split responsibilities |
| Copy-pasted logic | Drifts out of sync | Reuse a shared helper |
| Dead / commented code | Confuses readers | Delete it |

## Verify before you flag

A flag that turns out to be the house style wastes the team's trust. After spotting an issue, `Grep` the codebase to confirm it is actually anomalous. If the "problem" pattern is used consistently everywhere, the existing convention wins — report it only if it is genuinely harmful.

## Report format

For each finding:
- **Severity**: Critical / High / Medium / Low
- **Location**: `file:line`
- **Issue**: what is wrong, in one sentence
- **Suggestion**: the specific change to make

## Examples

Early returns over nesting:

```python
# Hard to follow — the real work is buried three levels deep
def process(data):
    if data:
        if data.is_valid():
            if data.has_permission():
                return do_work(data)

# Each precondition is explicit and the happy path is flat
def process(data):
    if not data:
        return None
    if not data.is_valid():
        raise ValueError("invalid data")
    if not data.has_permission():
        raise PermissionError("access denied")
    return do_work(data)
```

Avoid the N+1 query — it passes tests but degrades silently at scale:

```python
# One query per user
for user in users:
    posts = db.query(Post).filter(Post.user_id == user.id).all()

# One query total
users = db.query(User).options(joinedload(User.posts)).all()
```
