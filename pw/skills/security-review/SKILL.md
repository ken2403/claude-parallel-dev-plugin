---
name: security-review
description: Security review checklist for code changes. Automatically activates when reviewing security-sensitive code, authentication, authorization, or data handling. Use when user asks to "check security", "review for vulnerabilities", "audit code", or when changes touch auth, crypto, user input, or API endpoints.
allowed-tools: Read, Grep, Glob
metadata:
    author: ken2403
    version: 1.2.0
---

# Security Review Checklist

Apply these security checks when reviewing or writing code that handles sensitive operations.

## Instructions

### Step 1: Identify Security-Sensitive Areas

Scan the changed files for:
- Authentication / authorization logic
- User input handling
- Database queries
- API endpoints
- File operations
- Cryptographic operations
- Secrets / credentials

### Step 2: Check Security Controls

Review authentication, authorization, and input validation controls.
For the detailed checklist, consult `references/checklist.md`.

### Step 3: Scan for Dangerous Patterns

Use Grep to search for these red-flag patterns in the codebase:

```
eval(user_input)           # Code injection
exec(user_input)           # Code injection
os.system(user_input)      # Command injection
f"SELECT * FROM {table}"   # SQL injection
innerHTML = userData       # XSS
password = "hardcoded"     # Hardcoded secret
verify=False               # SSL verification disabled
shell=True                 # Shell injection risk
pickle.loads(              # Unsafe deserialization
yaml.load(                 # Unsafe YAML loading
```

For complete vulnerability patterns and secure alternatives, consult `references/vulnerabilities.md`.

### Step 4: Verify Data Protection

- Sensitive data encrypted at rest and in transit (TLS)
- No secrets in source code (use environment variables or vault)
- No sensitive data in logs
- PII handled according to regulations
- API keys rotatable, different per environment

### Step 5: Validate Findings

For each flagged issue:
1. Use Grep to check if the pattern is mitigated elsewhere (middleware, wrappers, framework protections)
2. Check framework-level protections before reporting (e.g., Django ORM, React JSX auto-escaping)
3. Verify the input source — internal/trusted sources may not need the same controls
4. Classify severity:
   - **Critical**: Remote code execution, authentication bypass, data breach
   - **High**: SQL injection, XSS, privilege escalation
   - **Medium**: Missing rate limiting, verbose error messages, weak encryption
   - **Low**: Informational findings, minor configuration issues

### Step 6: Final Security Checklist

- [ ] No injection vulnerabilities (SQL, XSS, Command)
- [ ] Authentication and authorization properly implemented
- [ ] All user input validated
- [ ] Secrets not hardcoded
- [ ] Sensitive data encrypted
- [ ] Security events logged (without sensitive data)
- [ ] Rate limiting on public endpoints
- [ ] CORS configured correctly
- [ ] Dependencies free of known vulnerabilities

## Report Format

For each finding:
- **Severity**: Critical / High / Medium / Low
- **Location**: file:line
- **Issue**: Brief description
- **Suggestion**: Specific fix or secure alternative

## Examples

### Example 1: SQL Injection Prevention

```python
# INSECURE - SQL injection
query = f"SELECT * FROM users WHERE name = '{user_input}'"

# SECURE - Parameterized query
query = "SELECT * FROM users WHERE name = %s"
cursor.execute(query, (user_input,))
```

### Example 2: XSS Prevention

```javascript
// INSECURE - XSS via innerHTML
element.innerHTML = userComment;

// SECURE - Use textContent or sanitization
element.textContent = userComment;
// or use DOMPurify for HTML content
element.innerHTML = DOMPurify.sanitize(userComment);
```

### Example 3: Secret Management

```python
# INSECURE - Hardcoded secret
API_KEY = "sk-abc123..."

# SECURE - Environment variable
API_KEY = os.environ["API_KEY"]
```

## Common Issues

If security review seems incomplete:
1. Use Grep to find all usages of the flagged pattern across the codebase
2. Check framework-level middleware (auth, CSRF, etc.)
3. Consult `references/vulnerabilities.md` for the full OWASP Top 10 mapping
