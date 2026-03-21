# Security Policy

## Reporting Vulnerabilities

If you discover a security vulnerability, please report it privately:

- **Email:** yaniv@golan.name
- **Do NOT** open a public GitHub issue for security vulnerabilities

I will acknowledge receipt within 48 hours and provide a fix timeline.

## Scope

Security issues in scope:

- Credential exposure (webhook URLs, API keys leaking in logs/output)
- Command injection in CLI argument parsing
- ENML/HTML injection in note content processing
- Config file permission issues
- Make.com blueprint files containing personal data

## Out of Scope

- Evernote API security (report to Evernote directly)
- Make.com platform security (report to Make.com directly)
- Rate limiting / denial of service (by design, xev-cli doesn't retry)

## Security Design

- Config files stored with `0600` permissions
- Webhook URLs masked in `--trace` and `config show` output
- API tokens never stored in config (used only during `config setup --auto`)
- Blueprint files sanitized before committing (no account IDs or webhook hooks)
- No `eval` used in config parsing (`printf -v` instead)
