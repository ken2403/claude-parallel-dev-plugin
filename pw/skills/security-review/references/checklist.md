# Security Review Detailed Checklist

## Authentication

- [ ] Authentication required for sensitive endpoints
- [ ] Strong password requirements enforced
- [ ] Passwords hashed with secure algorithm (bcrypt, argon2)
- [ ] Session tokens are cryptographically random
- [ ] Session expiration implemented
- [ ] Logout invalidates session properly
- [ ] Multi-factor authentication for high-privilege operations
- [ ] Account lockout after failed attempts

## Authorization

- [ ] Authorization checked before data access
- [ ] Role-based or attribute-based access control
- [ ] Principle of least privilege applied
- [ ] Ownership verified before operations
- [ ] Admin functions properly protected
- [ ] No insecure direct object references (IDOR)
- [ ] API endpoints enforce authorization consistently

## Input Validation

- [ ] All user input validated
- [ ] Input length limits enforced
- [ ] Input type/format validated
- [ ] Whitelist validation preferred over blacklist
- [ ] Validation on server-side (not just client)
- [ ] File upload validation (type, size, content)
- [ ] URL/redirect validation (prevent open redirects)

## Injection Prevention

### SQL Injection
- [ ] Parameterized queries / prepared statements
- [ ] ORM used correctly
- [ ] No string concatenation in queries
- [ ] Stored procedures use parameters

### XSS (Cross-Site Scripting)
- [ ] Output encoding/escaping
- [ ] Content Security Policy headers
- [ ] No innerHTML with user data
- [ ] Template engine auto-escaping enabled

### Command Injection
- [ ] No shell commands with user input
- [ ] If unavoidable, strict whitelisting
- [ ] Use subprocess with list arguments, not shell=True

### Other Injection
- [ ] LDAP injection prevention
- [ ] XML external entity (XXE) prevention
- [ ] Server-side template injection prevention

## Data Protection

- [ ] Sensitive data encrypted at rest
- [ ] Sensitive data encrypted in transit (TLS)
- [ ] PII handled according to regulations
- [ ] Data minimization (collect only needed data)
- [ ] Secure deletion when required
- [ ] Backup data also encrypted

## Secrets Management

- [ ] No hardcoded credentials
- [ ] No secrets in source code
- [ ] Secrets in environment variables or vault
- [ ] API keys rotatable
- [ ] Different secrets per environment
- [ ] .gitignore covers secret files (.env, credentials.json)

## Logging and Monitoring

- [ ] Security events logged
- [ ] No sensitive data in logs
- [ ] Failed authentication attempts logged
- [ ] Logs tamper-resistant
- [ ] Alerting on suspicious activity
- [ ] Audit trail for privileged operations

## API Security

- [ ] Rate limiting implemented
- [ ] CORS configured correctly
- [ ] API versioning in place
- [ ] Proper HTTP methods used
- [ ] Sensitive operations use POST/PUT/DELETE
- [ ] Request size limits enforced
- [ ] API authentication (tokens, not just cookies)
