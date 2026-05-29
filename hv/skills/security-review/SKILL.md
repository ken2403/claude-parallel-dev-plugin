---
name: security-review
description: Security review for code changes — thinks like an attacker about input validation, authz/authn, secrets, injection (SQL/command/path/template), unsafe deserialization, SSRF, crypto misuse, dependency risk, and logging of sensitive data. Use this whenever you implement or review anything touching auth, crypto, user input, secrets, API endpoints, file paths, or data handling, and when asked to "check security", "review for vulnerabilities", or "audit". Auto-activates during /hv:build-feature and /hv:review-pr. Security must never regress in autonomous unattended runs — so treat it as non-negotiable, not optional.
allowed-tools: Read, Grep, Glob, Bash
---

# Security Review

When changes can merge with little or no human review, the one thing review must never let through is a security regression — because no one is watching each run. So review the change the way an attacker reads it: assume every input is hostile, every boundary is probed, and every secret will leak if it can.

This applies when implementing (build it secure the first time) and when reviewing (a feature is not done if it opens a hole).

## Step 1 — Find the attack surface

Scan the diff for the places attackers actually target:

- Anything that handles **user input** (request bodies, query params, headers, file uploads, CLI args).
- **Auth / authz** logic — login, sessions, tokens, permission checks, ownership checks.
- **Data egress**: SQL/NoSQL queries, shell commands, file paths, template rendering, outbound HTTP.
- **Secrets**: API keys, passwords, tokens, signing keys.
- **Crypto**: hashing, encryption, randomness, signature verification.
- **Deserialization** of untrusted data.

If the diff touches none of these, the surface is small — say so and move on. Do not invent risk where there is none.

## Step 2 — Think like an attacker, by category

For each item below, ask "what does the attacker send to break this?"

**Injection** — untrusted data reaching an interpreter.
- SQL: string-built queries. Demand parameterized queries / prepared statements.
- Command: `os.system`, `subprocess(..., shell=True)`, backticks with interpolated input. Demand arg arrays, no shell.
- Path traversal: user input in file paths (`../../etc/passwd`). Demand canonicalize + confirm it stays under an allowed root.
- Template / SSTI: user input rendered as a template, not data.
- XSS: user data into HTML without escaping (`innerHTML`, `dangerouslySetInnerHTML`).

**AuthN / AuthZ** — the most common real-world breach.
- Every protected route checks authentication.
- Authorization checks **ownership**, not just "logged in" — can user A pass user B's id and act on it (IDOR)?
- No client-supplied role/permission trusted without server verification.
- Sessions/tokens expire, rotate, and are invalidated on logout.

**Secrets** — never in source.
- No hardcoded keys/passwords/tokens. They come from env or a vault, differ per environment, and are rotatable.
- `Grep` the diff for the patterns below before approving.

**SSRF** — user-controlled URLs fetched server-side.
- Validate against an allowlist; block internal/metadata addresses (`169.254.169.254`, `localhost`, private ranges).

**Unsafe deserialization** — `pickle.loads`, `yaml.load` (vs `safe_load`), Java/PHP native deserialization on untrusted bytes.

**Crypto misuse** — MD5/SHA1 for passwords (use bcrypt/argon2), home-rolled crypto, hardcoded IVs, `Math.random()` for tokens, `verify=False` / disabled TLS verification.

**Sensitive data in logs** — passwords, tokens, full PII, card numbers must not be logged or echoed in error responses.

**Dependencies** — new/updated deps: any known CVEs? Pinned? From a trusted source?

## Step 3 — Grep for the red flags

```
eval(            exec(            os.system(        shell=True
SELECT .* +      f"SELECT         innerHTML        dangerouslySetInnerHTML
pickle.loads(    yaml.load(       verify=False      md5(    sha1(
password =       api_key =        secret =          Math.random(
```

## Step 4 — Confirm before reporting

Frameworks mitigate a lot. Before flagging, check whether the risk is already handled:
- ORM parameterizes queries; JSX/template engine auto-escapes; framework middleware enforces CSRF/auth.
- Trace the input's **source** — data from a trusted internal service is not the same threat as raw request input.

A false positive that blocks an autonomous run is costly. Verify with `Grep`/`Read` that the mitigation is real, then report only genuine exposure.

## Step 5 — Classify and report

- **Critical**: RCE, auth bypass, data breach, secret exposure.
- **High**: SQL injection, stored XSS, IDOR, privilege escalation, SSRF.
- **Medium**: missing rate limiting, weak crypto, verbose errors leaking internals.
- **Low**: defense-in-depth gaps, informational.

For each finding:
- **Severity**, **Location** (`file:line`), **Issue** (what an attacker does with it), **Suggestion** (the secure fix).

## Final checklist

- [ ] All untrusted input validated / parameterized — no injection (SQL, command, path, template, XSS)
- [ ] AuthN on protected routes; AuthZ checks ownership (no IDOR)
- [ ] No hardcoded secrets; from env/vault, per-environment, rotatable
- [ ] No unsafe deserialization of untrusted data
- [ ] No SSRF — outbound URLs validated against an allowlist
- [ ] Strong crypto, secure randomness, TLS verification on
- [ ] No secrets / PII in logs or error responses
- [ ] New dependencies free of known CVEs

## Examples

```python
# SQL injection — attacker sends name = "'; DROP TABLE users;--"
query = f"SELECT * FROM users WHERE name = '{user_input}'"
# Parameterized — input can never change the query structure
cursor.execute("SELECT * FROM users WHERE name = %s", (user_input,))
```

```javascript
// XSS — userComment renders as HTML
element.innerHTML = userComment;
// Safe — treated as text, or sanitized if HTML is required
element.textContent = userComment;
element.innerHTML = DOMPurify.sanitize(userComment);
```

```python
# Secret in source — leaks via git history forever
API_KEY = "sk-abc123..."
# From the environment
API_KEY = os.environ["API_KEY"]
```
