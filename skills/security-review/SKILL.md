---
name: security-review
description: Security review checklist for code changes. Automatically activates when reviewing security-sensitive code, authentication, authorization, or data handling. Use when user asks to "check security", "review for vulnerabilities", "audit code", or when changes touch auth, crypto, user input, or API endpoints.
allowed-tools: Read, Grep, Glob
metadata:
    author: ken2403
    version: 1.1.0
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

### Step 2: Check Critical Security Controls

**Authentication**:
- Authentication required for sensitive endpoints
- Passwords hashed with secure algorithm (bcrypt, argon2)
- Session tokens are cryptographically random with expiration

**Authorization**:
- Authorization checked before data access
- Principle of least privilege applied
- Ownership verified before operations

**Input Validation**:
- All user input validated on server-side
- Input length limits enforced
- Whitelist validation preferred over blacklist

For the full detailed checklist, consult `references/checklist.md`.

### Step 3: Scan for Dangerous Patterns

Flag these red flags immediately:

```
eval(user_input)           # Code injection
exec(user_input)           # Code injection
os.system(user_input)      # Command injection
f"SELECT * FROM {table}"   # SQL injection
innerHTML = userData       # XSS
password = "hardcoded"     # Hardcoded secret
verify=False               # SSL verification disabled
```

For complete vulnerability patterns and secure alternatives, consult `references/vulnerabilities.md`.

### Step 4: Verify Data Protection

- Sensitive data encrypted at rest and in transit (TLS)
- No secrets in source code (use environment variables or vault)
- No sensitive data in logs
- PII handled according to regulations
- API keys rotatable, different per environment

### Step 5: Final Security Checklist

- [ ] No injection vulnerabilities (SQL, XSS, Command)
- [ ] Authentication and authorization properly implemented
- [ ] All user input validated
- [ ] Secrets not hardcoded
- [ ] Sensitive data encrypted
- [ ] Security events logged (without sensitive data)
- [ ] Rate limiting on public endpoints
- [ ] CORS configured correctly
- [ ] Dependencies free of known vulnerabilities

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

### False Positives

If the skill flags code that is actually safe:
1. Check if the input source is trusted (internal, not user-facing)
2. Verify if a framework-level protection is already in place
3. Document the safety justification in a comment

### Missing Context

If security review seems incomplete:
1. Use `Grep` to find all usages of the flagged pattern
2. Check framework-level middleware (auth, CSRF, etc.)
3. Consult `references/vulnerabilities.md` for the full OWASP Top 10 mapping
