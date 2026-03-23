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

## Prerequisites

### Find xev-cli

Search for xev-cli in known locations:

```bash
XEV=""
for p in \
  "$(command -v xev-cli 2>/dev/null)" \
  "$(find /sessions/*/mnt/.local-plugins/cache/xev-evernote-marketplace -name xev-cli -path '*/bin/*' 2>/dev/null | head -1)" \
  "${CLAUDE_PLUGIN_ROOT:-}/xev-cli/bin/xev-cli" \
  ./xev-cli/bin/xev-cli \
  ~/Documents/code/evernote-mcp/xev-cli/bin/xev-cli; do
  [[ -n "$p" && -x "$p" ]] && XEV="$p" && break
done
[[ -n "$XEV" ]] && echo "FOUND: $XEV" || echo "NOT_FOUND"
```

If not found, tell the user to install the plugin or clone the repo.

**IMPORTANT:** Use `"$XEV"` (the resolved path) for ALL commands below. Global flags like `--progress` go BEFORE the subcommand.

### Find .env for auto-discovery

xev-cli can auto-discover Make.com webhook URLs if `MAKE_API_KEY` and `MAKE_TEAM_ID` are available. Set `XEV_DOTENV_DIR` to the directory containing `.env`:

```bash
# Find .env in mounted folders (Cowork) or current project
for d in /Users/yaniv/Documents/code/evernote-mcp ./mnt/evernote-mcp "$PWD"; do
  [[ -f "$d/.env" ]] && grep -q MAKE_API_KEY "$d/.env" 2>/dev/null && export XEV_DOTENV_DIR="$d" && break
done
echo "XEV_DOTENV_DIR=${XEV_DOTENV_DIR:-NOT_SET}"
```

### Verify configuration

**Note:** `XEV_DOTENV_DIR` must be set BEFORE running config check.

```bash
"$XEV" --progress never config check
```

**If this succeeds** — proceed to the workflows below.

**If this fails** — tell the user:

> "xev-cli needs Make.com credentials. Create a `.env` file with `MAKE_API_KEY` and `MAKE_TEAM_ID`, and ensure it's in a mounted folder (Cowork) or set `XEV_DOTENV_DIR` to its directory."

### IMPORTANT: Do NOT run `config setup --auto` automatically

**NEVER run `config setup --auto` without explicit user instruction.** It creates new Make.com scenarios (costs credits, creates duplicates, requires manual Evernote connection in Make.com UI). Always ask the user first.

## Command Syntax

Global flags (`--progress`, `--trace`, `--profile`, `--dotenv`) go **BEFORE** the subcommand:

```
"$XEV" [global-flags] <subcommand> [subcommand-args]
```

Examples:
- `"$XEV" --progress never search "query" --limit 10`
- `"$XEV" --progress never --trace get "note-id" --format markdown`

## Workflow: Finding Information

### Step 1: Search

```bash
"$XEV" --progress never search "<query>" --limit 10 --output human
```

For notebook-specific searches:
```bash
"$XEV" --progress never search "<query>" --notebook "<name>" --limit 10 --output human
```

Present results as a clean list — **never dump raw JSON to the user**. Summarize: title, notebook, date.

### Step 2: Read a Note

```bash
"$XEV" --progress never get "<note-id>" --format markdown | jq -r '.data.content'
```

To get metadata alongside content:
```bash
"$XEV" --progress never get "<note-id>" --format markdown | jq '{title: .data.title, notebook: .data.notebook, updated: .data.updated, content: .data.content}'
```

Present the content naturally — format it, summarize if long, highlight what the user asked about.

### Step 3: List Notebooks

```bash
"$XEV" --progress never notebooks --output human
```

## Workflow: Creating Notes

### Step 1: Gather Information

Before creating, confirm with the user:
- **Title** for the note
- **Notebook** to save to (list notebooks if unsure)
- **Content** (markdown format — converted to ENML automatically)

### Step 2: Create

```bash
"$XEV" --progress never create --title "<title>" --notebook "<notebook-name>" --content "<markdown content>" | jq '.'
```

For multi-line content, use `--content-file`:
```bash
cat > /tmp/xev-note-content.md << 'NOTEOF'
# Meeting Notes

Content here...
NOTEOF
"$XEV" --progress never create --title "<title>" --notebook "<notebook-name>" --content-file /tmp/xev-note-content.md | jq '.'
rm -f /tmp/xev-note-content.md
```

## Workflow: Updating Notes

### Replace content:
```bash
"$XEV" --progress never update "<note-id>" --content "<new markdown content>" | jq '.'
```

### Append to existing note:
```bash
"$XEV" --progress never update "<note-id>" --append --content "<content to add>" | jq '.'
```

### Update title only:
```bash
"$XEV" --progress never update "<note-id>" --title "<new title>" | jq '.'
```

## Output Handling

- All commands output JSON to stdout, progress/errors to stderr
- `--progress never` (global flag, before subcommand) suppresses progress messages
- **Do NOT use `2>/dev/null`** — it hides error messages
- Use `--output human` for search/notebooks when presenting to user
- **Never show raw JSON to the user** — parse and present naturally

## Error Handling

```bash
result=$("$XEV" --progress never search "query")
if echo "$result" | jq -e '.ok == false' >/dev/null 2>&1; then
  error_code=$(echo "$result" | jq -r '.error.code')
  error_msg=$(echo "$result" | jq -r '.error.message')
fi
```

| Error Code | Meaning | What to Do |
|-----------|---------|-----------|
| RATE_LIMITED | Evernote API rate limit | Wait the specified seconds, then retry |
| TIMEOUT | Make.com scenario timed out | Retry once. If persistent, check Make.com. |
| EVERNOTE_ERROR | Evernote rejected the request | Check note ID, notebook name, or content |
| NOT_FOUND | Note or notebook not found | Verify the ID. Run `"$XEV" --progress never notebooks` |
| CONFIG_ERROR | xev-cli not configured | Ensure XEV_DOTENV_DIR is set and .env has credentials |
| AUTH_FAILED | Webhook URL invalid | Reconfigure webhooks |

For RATE_LIMITED errors, tell the user how long to wait and offer to retry.

## Examples

**User: "Find my notes about the Viewz meeting"**
1. `"$XEV" --progress never search "Viewz meeting" --limit 5 --output human`
2. Present results: "I found 3 notes about Viewz meetings..."
3. If user wants details → `"$XEV" --progress never get <id> --format markdown`

**User: "Save these action items to Evernote"**
1. Ask which notebook
2. `"$XEV" --progress never create --title "Action Items" --notebook "Work" --content "..."`
3. "Created note 'Action Items' in Work notebook."

## Reference

For full CLI syntax, see `references/cli-reference.md`.
