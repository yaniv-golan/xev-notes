---
name: xev-evernote
description: "Search, read, create, and update Evernote notes using xev-cli. Use when user asks about Evernote notes, work notes, meeting notes, wants to find information in notes, read note content, create new notes, or update existing notes. Also use when user mentions 'xev', 'xev-cli', 'search my notes', 'check my Evernote', 'note from last week', or references information likely stored in Evernote notebooks."
license: MIT
metadata:
  author: Yaniv Golan
  version: "0.1.0"
  compatibility: "Requires xev-cli (bash), jq, curl, and pandoc for write operations."
---

# Evernote Access

Search, read, create, and update Evernote notes via xev-cli.

## Prerequisites

Silently verify xev-cli is configured:

```bash
xev-cli config check 2>/dev/null
```

If this fails, tell the user: "xev-cli is not configured. Run `xev-cli config setup --auto` to set up Make.com integration, or see the setup guide at `docs/make-com-setup.md`."

If `xev-cli` is not found on PATH, check common locations:

```bash
for p in ./xev-cli/bin/xev-cli ~/Documents/code/evernote-mcp/xev-cli/bin/xev-cli; do
  [[ -x "$p" ]] && echo "FOUND:$p" && break
done
```

Use the found path for all subsequent commands. If not found, tell the user to install xev-cli.

## Workflow: Finding Information

Use this when the user asks to find, search, or read notes.

### Step 1: Search

```bash
xev-cli search "<query>" --limit 10 --output human 2>/dev/null
```

For notebook-specific searches:
```bash
xev-cli search "<query>" --notebook "<name>" --limit 10 --output human 2>/dev/null
```

Present results as a clean list — **never dump raw JSON to the user**. Summarize: title, notebook, date.

If no results, suggest broadening the query or trying different keywords.

### Step 2: Read a Note

When the user picks a note (or you need its content):

```bash
xev-cli get "<note-id>" --format markdown 2>/dev/null | jq -r '.data.content' 2>/dev/null
```

To get metadata alongside content:
```bash
xev-cli get "<note-id>" --format markdown 2>/dev/null | jq '{title: .data.title, notebook: .data.notebook, updated: .data.updated, content: .data.content}' 2>/dev/null
```

Present the content naturally — format it, summarize if long, highlight what the user asked about.

### Step 3: List Notebooks

If the user needs to know what notebooks exist:

```bash
xev-cli notebooks --output human 2>/dev/null
```

## Workflow: Creating Notes

Use this when the user wants to save something to Evernote.

### Step 1: Gather Information

Before creating, confirm with the user:
- **Title** for the note
- **Notebook** to save to (list notebooks if unsure)
- **Content** (markdown format — will be converted to ENML automatically)

### Step 2: Create

```bash
xev-cli create --title "<title>" --notebook "<notebook-name>" --content "<markdown content>" 2>/dev/null | jq '.' 2>/dev/null
```

For multi-line content, use `--content-file`:
```bash
cat > /tmp/xev-note-content.md << 'NOTEOF'
# Meeting Notes

Content here...
NOTEOF
xev-cli create --title "<title>" --notebook "<notebook-name>" --content-file /tmp/xev-note-content.md 2>/dev/null | jq '.' 2>/dev/null
rm -f /tmp/xev-note-content.md
```

Report the created note ID back to the user.

## Workflow: Updating Notes

### Replace content:
```bash
xev-cli update "<note-id>" --content "<new markdown content>" 2>/dev/null | jq '.' 2>/dev/null
```

### Append to existing note:
```bash
xev-cli update "<note-id>" --append --content "<content to add>" 2>/dev/null | jq '.' 2>/dev/null
```

### Update title only:
```bash
xev-cli update "<note-id>" --title "<new title>" 2>/dev/null | jq '.' 2>/dev/null
```

## Output Handling

- All commands output JSON to stdout and progress to stderr
- Redirect stderr with `2>/dev/null` for clean output
- Use `--output human` for search/notebooks when presenting to user
- Use `--output json` or default JSONL when processing programmatically
- **Never show raw JSON to the user** — parse and present naturally

## Error Handling

Check for errors in JSON responses:

```bash
result=$(xev-cli search "query" 2>/dev/null)
if echo "$result" | jq -e '.ok == false' >/dev/null 2>&1; then
  error_code=$(echo "$result" | jq -r '.error.code')
  error_msg=$(echo "$result" | jq -r '.error.message')
fi
```

| Error Code | Meaning | What to Do |
|-----------|---------|-----------|
| RATE_LIMITED | Evernote API rate limit | Wait the specified seconds, then retry |
| TIMEOUT | Make.com scenario timed out | Retry once. If persistent, check Make.com. |
| EVERNOTE_ERROR | Evernote rejected the request | Check note ID, notebook name, or content format |
| NOT_FOUND | Note or notebook not found | Verify the ID. Run `xev-cli notebooks` to list notebooks. |
| CONFIG_ERROR | xev-cli not configured | Run `xev-cli config setup --auto` |
| AUTH_FAILED | Webhook URL invalid | Webhook URLs may have changed. Reconfigure. |

For RATE_LIMITED errors, tell the user how long to wait and offer to retry.

## Examples

**User: "Find my notes about the Viewz meeting"**
1. `xev-cli search "Viewz meeting" --limit 5 --output human`
2. Present results: "I found 3 notes about Viewz meetings..."
3. If user wants details → `xev-cli get <id> --format markdown`

**User: "Save these action items to Evernote"**
1. Ask which notebook
2. `xev-cli create --title "Action Items - 2026-03-21" --notebook "Work" --content "..."`
3. "Created note 'Action Items - 2026-03-21' in Work notebook."

**User: "Add a note to my meeting notes from today"**
1. `xev-cli search "meeting" --limit 5` to find today's note
2. `xev-cli update <id> --append --content "## Follow-up\n- Item 1\n- Item 2"`
3. "Added follow-up items to your meeting notes."

## Reference

For full CLI syntax, see `references/cli-reference.md`.
