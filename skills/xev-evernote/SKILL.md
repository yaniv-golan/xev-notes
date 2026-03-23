---
name: xev-evernote
description: "Search, read, create, and update Evernote notes using xev-cli. Use when user asks about Evernote notes, work notes, meeting notes, wants to find information in notes, read note content, create new notes, or update existing notes. Also use when user mentions 'xev', 'xev-cli', 'search my notes', 'check my Evernote', 'note from last week', or references information likely stored in Evernote notebooks."
license: MIT
metadata:
  author: Yaniv Golan
  version: "0.2.1"
  compatibility: "Requires xev-cli (bash), jq, curl, and pandoc for write operations."
---

# Evernote Access

Search, read, create, and update Evernote notes via xev-cli.

## Prerequisites

### Find xev-cli

When installed as a plugin, xev-cli is on PATH (set by the SessionStart hook). Verify:

```bash
command -v xev-cli >/dev/null && echo "FOUND" || echo "NOT_FOUND"
```

If not on PATH, try the plugin root:

```bash
XEV_CLI="${CLAUDE_PLUGIN_ROOT:-}/xev-cli/bin/xev-cli"
[[ -x "$XEV_CLI" ]] && echo "FOUND" || echo "NOT_FOUND"
```

If still not found, check common locations:

```bash
for p in ./xev-cli/bin/xev-cli ~/Documents/code/evernote-mcp/xev-cli/bin/xev-cli; do
  [[ -x "$p" ]] && echo "FOUND:$p" && break
done
```

Use the found path for all commands. If `xev-cli` is on PATH, use it directly. Otherwise use `"$XEV_CLI"`.

### Verify configuration

```bash
xev-cli config check --progress never
```

**If this succeeds** — you're ready to go. Proceed to the workflows below.

**If this fails** — the Make.com webhooks are not configured. Tell the user:

> "xev-cli needs Make.com webhook URLs to connect to Evernote. You have two options:
> 1. **Recommended:** Create a `.env` file with `MAKE_API_KEY` and `MAKE_TEAM_ID`, then set `XEV_DOTENV_DIR` to the directory containing it. xev-cli will auto-discover webhook URLs.
> 2. **Manual:** Run `xev-cli config setup --auto` from a terminal with Make.com credentials."

### IMPORTANT: Do NOT run `config setup --auto` automatically

**NEVER run `xev-cli config setup --auto` without explicit user instruction.** This command creates new Make.com scenarios, which:
- Costs Make.com operations credits
- Creates duplicate scenarios if run multiple times
- Requires the user to manually connect Evernote and activate each scenario in the Make.com UI afterward

If configuration fails, **always ask the user** what to do rather than attempting auto-setup. The most common fix is ensuring the `.env` file is accessible (mounted folder in Cowork, or `XEV_DOTENV_DIR` set).

## Workflow: Finding Information

Use this when the user asks to find, search, or read notes.

### Step 1: Search

```bash
"$XEV_CLI" search "<query>" --limit 10 --output human --progress never
```

For notebook-specific searches:
```bash
"$XEV_CLI" search "<query>" --notebook "<name>" --limit 10 --output human --progress never
```

Present results as a clean list — **never dump raw JSON to the user**. Summarize: title, notebook, date.

If no results, suggest broadening the query or trying different keywords.

### Step 2: Read a Note

When the user picks a note (or you need its content):

```bash
"$XEV_CLI" get "<note-id>" --format markdown --progress never | jq -r '.data.content'
```

To get metadata alongside content:
```bash
"$XEV_CLI" get "<note-id>" --format markdown --progress never | jq '{title: .data.title, notebook: .data.notebook, updated: .data.updated, content: .data.content}'
```

Present the content naturally — format it, summarize if long, highlight what the user asked about.

### Step 3: List Notebooks

If the user needs to know what notebooks exist:

```bash
"$XEV_CLI" notebooks --output human --progress never
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
"$XEV_CLI" create --title "<title>" --notebook "<notebook-name>" --content "<markdown content>" --progress never | jq '.'
```

For multi-line content, use `--content-file`:
```bash
cat > /tmp/xev-note-content.md << 'NOTEOF'
# Meeting Notes

Content here...
NOTEOF
"$XEV_CLI" create --title "<title>" --notebook "<notebook-name>" --content-file /tmp/xev-note-content.md --progress never | jq '.'
rm -f /tmp/xev-note-content.md
```

Report the created note ID back to the user.

## Workflow: Updating Notes

### Replace content:
```bash
"$XEV_CLI" update "<note-id>" --content "<new markdown content>" --progress never | jq '.'
```

### Append to existing note:
```bash
"$XEV_CLI" update "<note-id>" --append --content "<content to add>" --progress never | jq '.'
```

### Update title only:
```bash
"$XEV_CLI" update "<note-id>" --title "<new title>" --progress never | jq '.'
```

## Output Handling

- All commands output JSON to stdout and progress/errors to stderr
- Use `--progress never` to suppress progress messages (cleaner than `2>/dev/null`)
- **Do NOT use `2>/dev/null`** — it hides error messages and makes failures silent. Instead, capture stderr separately or use `--progress never` to suppress only progress output.
- Use `--output human` for search/notebooks when presenting to user
- Use `--output json` or default JSONL when processing programmatically
- **Never show raw JSON to the user** — parse and present naturally
- If a command fails, check both stdout (JSON error) and stderr (diagnostic info)

## Error Handling

Check for errors in JSON responses:

```bash
result=$("$XEV_CLI" search "query" --progress never)
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
| NOT_FOUND | Note or notebook not found | Verify the ID. Run `"$XEV_CLI" notebooks` to list notebooks. |
| CONFIG_ERROR | xev-cli not configured | Run `"$XEV_CLI" config setup --auto` |
| AUTH_FAILED | Webhook URL invalid | Webhook URLs may have changed. Reconfigure. |

For RATE_LIMITED errors, tell the user how long to wait and offer to retry.

## Examples

**User: "Find my notes about the Viewz meeting"**
1. `"$XEV_CLI" search "Viewz meeting" --limit 5 --output human`
2. Present results: "I found 3 notes about Viewz meetings..."
3. If user wants details → `"$XEV_CLI" get <id> --format markdown`

**User: "Save these action items to Evernote"**
1. Ask which notebook
2. `"$XEV_CLI" create --title "Action Items - 2026-03-21" --notebook "Work" --content "..."`
3. "Created note 'Action Items - 2026-03-21' in Work notebook."

**User: "Add a note to my meeting notes from today"**
1. `"$XEV_CLI" search "meeting" --limit 5` to find today's note
2. `"$XEV_CLI" update <id> --append --content "## Follow-up\n- Item 1\n- Item 2"`
3. "Added follow-up items to your meeting notes."

## Reference

For full CLI syntax, see `references/cli-reference.md`.
