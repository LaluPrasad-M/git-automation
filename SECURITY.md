# Security Policy

## Supported Scope

Security reports should focus on:

- Credential or token handling
- Unsafe automation behavior that can cause unauthorized actions
- Policy bypass vulnerabilities
- Injection vulnerabilities in shell scripts or payload processing

## Reporting a Vulnerability

Please do not open a public issue for security vulnerabilities.

Report privately by contacting the repository owner through GitHub security reporting channels or direct private communication.

Include:

- Impact summary
- Reproduction steps
- Proof of concept (if available)
- Suggested mitigation (optional)

## Secrets and Operational Safety

- Never commit `.env` or tokens.
- Keep `.state/` untracked.
- Rotate credentials immediately if exposure is suspected.
- Use least-privilege PAT scopes for automation.
