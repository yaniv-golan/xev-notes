# xev-cli Reference

## Global Flags

```
--profile <name>   Config profile (default: "default")
--config-file <p>  Alternate config file path
--dotenv           Load .env from current directory
--trace            Debug output (URLs redacted)
--progress <mode>  auto|always|never (default: auto)
--version          Show version
--help             Show help
```

## Commands

### search

```bash
xev-cli search <query> [--notebook <name>] [--limit <n>] [--output jsonl|json|human]
```

- Default output: JSONL (one JSON object per line)
- Default limit: 20
- Query uses Evernote search grammar (see below)

Output fields: `id`, `title`, `notebook`, `notebook_id`, `updated`, `note_link`

### get

```bash
xev-cli get <note-id> [--format markdown|text|enml] [--output json|human]
```

- Default format: markdown (ENML converted via pandoc)
- `text`: plain text stripped of HTML
- `enml`: raw Evernote XML

Output fields: `id`, `title`, `notebook`, `updated`, `created`, `content`, `format`

### notebooks

```bash
xev-cli notebooks [--output json|jsonl|human]
```

Lists unique notebook name/ID pairs.

### create

```bash
xev-cli create --title <title> --notebook <name> [--content <markdown>] [--content-file <path>] [--output json|human]
```

- Notebook name is resolved to GUID automatically
- Content is converted from markdown to ENML
- Requires pandoc

### update

```bash
xev-cli update <note-id> [--title <title>] [--content <markdown>] [--content-file <path>] [--append] [--output json|human]
```

- Without `--append`: replaces content entirely
- With `--append`: adds content to end of existing note
- At least one of `--title`, `--content`, or `--content-file` required

### config

```bash
xev-cli config setup [--auto] [--profile <name>]   # Configure webhooks
xev-cli config show [--profile <name>]              # Show config (URLs masked)
xev-cli config check [--profile <name>] [--ping]    # Validate config
xev-cli config path                                  # Print config file path
```

## Evernote Search Grammar

The search query supports Evernote's search syntax:

| Syntax | Meaning |
|--------|---------|
| `meeting notes` | Notes containing both words |
| `"exact phrase"` | Exact phrase match |
| `notebook:Private` | Notes in specific notebook |
| `tag:important` | Notes with specific tag |
| `created:day-7` | Created in last 7 days |
| `updated:day-30` | Updated in last 30 days |
| `intitle:quarterly` | Word in title only |
| `any: cat dog` | Notes containing either word |

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Runtime error (API failure, not found, etc.) |
| 2 | Usage error (bad arguments, missing config) |
