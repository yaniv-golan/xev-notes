---
name: xev-evernote
description: "Search, read, create, and update Evernote notes using xev-cli. Use when user asks about Evernote notes, work notes, meeting notes, wants to find information in notes, read note content, create new notes, or update existing notes. Also use when user mentions 'xev', 'xev-cli', 'search my notes', 'check my Evernote', 'note from last week', or references information likely stored in Evernote notebooks."
license: MIT
metadata:
  author: Yaniv Golan
  version: "0.2.3"
  compatibility: "Requires xev-cli (bash), jq, curl, and pandoc for write operations."
---

# Evernote Access

Search, read, create, and update Evernote notes via xev-cli.

**Before using any command**, read `references/search-grammar.md` for Evernote search syntax and `references/error-codes.md` for error recovery.

## Setup (run once per session)

Each Bash call is a fresh shell. Variables don't persist. Run this setup block first to create a helper script that persists across calls:

```bash
# Find xev-cli
XEV=""
for p in \
  "$(command -v xev-cli 2>/dev/null)" \
  "$(find /sessions/*/mnt/.local-plugins/cache/xev-evernote* -name xev-cli -path '*/bin/*' 2>/dev/null | head -1)" \
  "${CLAUDE_PLUGIN_ROOT:-}/xev-cli/bin/xev-cli" \
  ./xev-cli/bin/xev-cli; do
  [[ -n "$p" && -x "$p" ]] && XEV="$p" && break
done

# Find .env with Make.com credentials
DOTENV=""
for d in ./mnt/[^.]*; do
  [[ -d "$d" && "$(basename "$d")" != "uploads" && -f "$d/.env" ]] && \
    grep -q MAKE_API_KEY "$d/.env" 2>/dev/null && DOTENV="$d" && break
done
[[ -z "$DOTENV" ]] && for d in "$PWD" "$HOME"; do
  [[ -f "$d/.env" ]] && grep -q MAKE_API_KEY "$d/.env" 2>/dev/null && DOTENV="$d" && break
done

# Write helper script (persists across Bash calls)
cat > /tmp/xev-run.sh << XEOF
#!/usr/bin/env bash
export XEV_DOTENV_DIR="$DOTENV"
exec "$XEV" --progress never "\$@"
XEOF
chmod +x /tmp/xev-run.sh

# Verify
/tmp/xev-run.sh config check && echo "READY" || echo "SETUP FAILED"
```

If setup fails, tell the user: "xev-cli needs a `.env` file with `MAKE_API_KEY` and `MAKE_TEAM_ID` in a mounted folder."

### IMPORTANT: Do NOT run `config setup --auto`

**NEVER run `config setup --auto` without explicit user instruction.** It creates new Make.com scenarios (costs credits, creates duplicates). Always ask the user first.

## Commands

After setup, use `/tmp/xev-run.sh` for all commands. It handles path resolution, credentials, and progress suppression.

**Global flags** (`--progress`, `--trace`, `--profile`) go **BEFORE** the subcommand. Subcommand flags go after.

### Search

```bash
/tmp/xev-run.sh search "<query>" --limit 5 --output human
```

Evernote search grammar (see `references/search-grammar.md` for full reference):
- `intitle:planning` — match in title only
- `notebook:Private` — restrict to notebook
- `tag:important` — by tag
- `created:day-7` — created in last 7 days
- `"exact phrase"` — exact match

**Rate limit guidance:** Use small `--limit` values (5-10, not 20+). Each search consumes API quota. If you hit RATE_LIMITED, wait the specified seconds — there's no workaround.

### Get Note

```bash
/tmp/xev-run.sh get "<note-id>" --format markdown | jq -r '.data.content'
```

With metadata:
```bash
/tmp/xev-run.sh get "<note-id>" --format markdown | jq '{title: .data.title, notebook: .data.notebook, content: .data.content}'
```

### List Notebooks

```bash
/tmp/xev-run.sh notebooks --output human
```

### Create Note

```bash
/tmp/xev-run.sh create --title "<title>" --notebook "<notebook-name>" --content "<markdown>" | jq '.'
```

For multi-line content:
```bash
cat > /tmp/xev-note.md << 'NOTEOF'
# Meeting Notes
Content here...
NOTEOF
/tmp/xev-run.sh create --title "<title>" --notebook "<name>" --content-file /tmp/xev-note.md | jq '.'
rm -f /tmp/xev-note.md
```

### Update Note

```bash
# Replace content
/tmp/xev-run.sh update "<note-id>" --content "<markdown>" | jq '.'

# Append to existing
/tmp/xev-run.sh update "<note-id>" --append --content "<content to add>" | jq '.'

# Update title only
/tmp/xev-run.sh update "<note-id>" --title "<new title>" | jq '.'
```

## Output Handling

- JSON to stdout, progress/errors to stderr
- `--progress never` (handled by /tmp/xev-run.sh) suppresses progress
- **Do NOT use `2>/dev/null`** — it hides errors
- Use `--output human` for search/notebooks when presenting to user
- **Never dump raw JSON** — parse and present naturally

## Error Handling

```bash
result=$(/tmp/xev-run.sh search "query")
if echo "$result" | jq -e '.ok == false' >/dev/null 2>&1; then
  echo "$result" | jq -r '.error | "\(.code): \(.message)"'
fi
```

| Error Code | Meaning | What to Do |
|-----------|---------|-----------|
| RATE_LIMITED | Evernote API rate limit | Tell user the wait time. Do NOT retry immediately. |
| TIMEOUT | Make.com webhook timed out | Retry once |
| EVERNOTE_ERROR | Evernote rejected request | Check note ID, notebook name, or query |
| NOT_FOUND | Note/notebook not found | Verify ID. List notebooks with `notebooks` |
| CONFIG_ERROR | Not configured | Check .env and XEV_DOTENV_DIR |

## Examples

**User: "Find my notes about Q4 planning"**
1. `/tmp/xev-run.sh search "Q4 planning" --limit 5 --output human`
2. Present: "I found 3 notes..."
3. User picks one → `/tmp/xev-run.sh get <id> --format markdown | jq -r '.data.content'`

**User: "Save these action items to Evernote"**
1. Ask which notebook (or list with `notebooks`)
2. `/tmp/xev-run.sh create --title "Action Items" --notebook "Work" --content "..."`

**User: "Append to my meeting notes"**
1. Find the note: `/tmp/xev-run.sh search "meeting" --limit 5`
2. `/tmp/xev-run.sh update <id> --append --content "## Follow-up\n- Item 1"`
