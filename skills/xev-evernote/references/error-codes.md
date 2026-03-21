# Error Codes

All xev-cli commands return JSON with `{"ok": false, "error": {"code": "...", "message": "..."}}` on failure.

## Error Code Reference

| Code | HTTP | Meaning | Recovery |
|------|------|---------|----------|
| `RATE_LIMITED` | 200 | Evernote API rate limit reached | Wait the specified seconds, then retry |
| `TIMEOUT` | 200 | Make.com scenario timed out (180s) | Retry once. If persistent, check Make.com scenario status |
| `EVERNOTE_ERROR` | 200 | Evernote rejected the request | Check note ID, notebook name, or content format. Message has details |
| `NOT_FOUND` | - | Note or notebook not found | Verify the ID/name. Run `xev-cli notebooks` to list notebooks |
| `AUTH_FAILED` | 401/403 | Webhook URL invalid or expired | Run `xev-cli config setup` to reconfigure webhook URLs |
| `MAKE_ERROR` | various | Make.com returned unexpected response | Check Make.com scenario history for details |
| `CONFIG_ERROR` | - | xev-cli not configured | Run `xev-cli config setup --auto` |
| `CONVERSION_ERROR` | - | Markdown to ENML conversion failed | Ensure pandoc is installed: `pandoc --version` |

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Runtime error (API failure, not found, etc.) — error JSON on stdout |
| 2 | Usage error (bad arguments, missing config) — message on stderr |

## Rate Limiting

Evernote enforces API rate limits. When hit:
- The error message includes the wait duration in seconds
- xev-cli does NOT retry automatically — retry logic is left to the caller
- Typical cooldown: 300-900 seconds (5-15 minutes)
- Heavy search queries (broad wildcards, high limits) consume more rate limit budget
