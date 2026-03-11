# Vulnerability Patterns and Secure Alternatives

## OWASP Top 10 Reference

1. **Broken Access Control** - Verify authorization on every request
2. **Cryptographic Failures** - Use strong, modern encryption (AES-256, RSA-2048+)
3. **Injection** - Parameterize all queries, escape all output
4. **Insecure Design** - Threat model considered, security by design
5. **Security Misconfiguration** - Secure defaults, disable unnecessary features
6. **Vulnerable Components** - Dependencies updated, known CVEs patched
7. **Authentication Failures** - Strong auth, MFA, session management
8. **Data Integrity Failures** - Verify signatures, use trusted sources
9. **Logging Failures** - Audit trail present, monitoring active
10. **SSRF** - Validate URLs, restrict internal network access

## Dangerous Code Patterns

### Code Injection
```python
# DANGEROUS
eval(user_input)
exec(user_input)
compile(user_input, '<string>', 'exec')

# SAFE
import ast
ast.literal_eval(user_input)  # Only for literal expressions
# Or use explicit parsing for the expected format
```

### Command Injection
```python
# DANGEROUS
os.system(f"convert {filename}")
subprocess.call(f"ls {directory}", shell=True)

# SAFE
subprocess.run(["convert", filename], check=True)
subprocess.run(["ls", directory], check=True)
```

### SQL Injection
```python
# DANGEROUS
cursor.execute(f"SELECT * FROM users WHERE id = {user_id}")
query = "SELECT * FROM users WHERE name = '" + name + "'"

# SAFE
cursor.execute("SELECT * FROM users WHERE id = %s", (user_id,))
# Or use ORM
User.objects.filter(id=user_id)
```

### XSS
```javascript
// DANGEROUS
element.innerHTML = userContent;
document.write(userInput);
$('#el').html(userData);

// SAFE
element.textContent = userContent;
element.innerHTML = DOMPurify.sanitize(userContent);
$('#el').text(userData);
```

### Path Traversal
```python
# DANGEROUS
filepath = os.path.join(BASE_DIR, user_filename)

# SAFE
filepath = os.path.join(BASE_DIR, user_filename)
resolved = os.path.realpath(filepath)
if not resolved.startswith(os.path.realpath(BASE_DIR)):
    raise ValueError("Path traversal detected")
```

### Deserialization
```python
# DANGEROUS
data = pickle.loads(user_data)
data = yaml.load(user_data)  # Without Loader

# SAFE
data = json.loads(user_data)
data = yaml.safe_load(user_data)
```

## Secure Alternatives Quick Reference

| Insecure | Secure Alternative |
|----------|-------------------|
| MD5/SHA1 for passwords | bcrypt/argon2 |
| `pickle.loads(user_data)` | JSON with validation |
| `eval()` / `exec()` | Explicit parsing |
| String concatenation SQL | Parameterized queries |
| Storing plaintext secrets | Environment variables / vault |
| `shell=True` in subprocess | List arguments without shell |
| `verify=False` in requests | Proper certificate validation |
| `innerHTML` with user data | `textContent` or DOMPurify |
| `yaml.load()` | `yaml.safe_load()` |
| Rolling your own crypto | Standard library / established packages |

## Framework-Specific Notes

### Django
- Use `{% autoescape %}` (enabled by default)
- Use `django.db.models` ORM, avoid raw SQL
- CSRF middleware is on by default - don't disable it

### Express/Node.js
- Use `helmet` for security headers
- Use `express-rate-limit` for rate limiting
- Use `express-validator` for input validation

### Flask
- Use `Markup.escape()` for output
- Use SQLAlchemy ORM with parameterized queries
- Set `SESSION_COOKIE_SECURE = True` in production

### React
- JSX auto-escapes by default - don't use `dangerouslySetInnerHTML`
- Validate props with PropTypes or TypeScript
- Use `Content-Security-Policy` headers
