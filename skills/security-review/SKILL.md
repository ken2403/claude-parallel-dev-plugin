---
name: security-review
description: Security review checklist for code changes. Automatically activates when reviewing security-sensitive code, authentication, authorization, or data handling.
allowed-tools: Read, Grep, Glob
---

# Security Review Checklist

Apply these security checks when reviewing or writing code that handles sensitive operations.

## Authentication

- [ ] Authentication required for sensitive endpoints
- [ ] Strong password requirements enforced
- [ ] Passwords hashed with secure algorithm (bcrypt, argon2)
- [ ] Session tokens are cryptographically random
- [ ] Session expiration implemented
- [ ] Logout invalidates session properly

## Authorization

- [ ] Authorization checked before data access
- [ ] Role-based or attribute-based access control
- [ ] Principle of least privilege applied
- [ ] Ownership verified before operations
- [ ] Admin functions properly protected

## Input Validation

- [ ] All user input validated
- [ ] Input length limits enforced
- [ ] Input type/format validated
- [ ] Whitelist validation preferred over blacklist
- [ ] Validation on server-side (not just client)

## Injection Prevention

### SQL Injection
- [ ] Parameterized queries / prepared statements
- [ ] ORM used correctly
- [ ] No string concatenation in queries

### XSS (Cross-Site Scripting)
- [ ] Output encoding/escaping
- [ ] Content Security Policy headers
- [ ] No innerHTML with user data

### Command Injection
- [ ] No shell commands with user input
- [ ] If unavoidable, strict whitelisting

## Data Protection

- [ ] Sensitive data encrypted at rest
- [ ] Sensitive data encrypted in transit (TLS)
- [ ] PII handled according to regulations
- [ ] Data minimization (collect only needed data)
- [ ] Secure deletion when required

## Secrets Management

- [ ] No hardcoded credentials
- [ ] No secrets in source code
- [ ] Secrets in environment variables or vault
- [ ] API keys rotatable
- [ ] Different secrets per environment

## Logging & Monitoring

- [ ] Security events logged
- [ ] No sensitive data in logs
- [ ] Failed authentication attempts logged
- [ ] Logs tamper-resistant
- [ ] Alerting on suspicious activity

## API Security

- [ ] Rate limiting implemented
- [ ] CORS configured correctly
- [ ] API versioning in place
- [ ] Proper HTTP methods used
- [ ] Sensitive operations use POST/PUT/DELETE

## Common Vulnerabilities (OWASP Top 10)

1. **Broken Access Control** - Verify authorization
2. **Cryptographic Failures** - Use strong encryption
3. **Injection** - Parameterize all queries
4. **Insecure Design** - Threat model considered
5. **Security Misconfiguration** - Secure defaults
6. **Vulnerable Components** - Dependencies updated
7. **Authentication Failures** - Strong auth
8. **Data Integrity Failures** - Verify signatures
9. **Logging Failures** - Audit trail present
10. **SSRF** - Validate URLs, restrict access

## Security Red Flags

Look for these patterns that often indicate security issues:

```
# Dangerous patterns
eval(user_input)           # Code injection
exec(user_input)           # Code injection
os.system(user_input)      # Command injection
f"SELECT * FROM {table}"   # SQL injection
innerHTML = userData       # XSS
password = "hardcoded"     # Hardcoded secret
verify=False               # SSL verification disabled
```

## Secure Alternatives

| Insecure | Secure Alternative |
|----------|-------------------|
| MD5/SHA1 for passwords | bcrypt/argon2 |
| `pickle.loads(user_data)` | JSON with validation |
| `eval()` | Explicit parsing |
| String concatenation SQL | Parameterized queries |
| Storing plaintext secrets | Environment variables |
