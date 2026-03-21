# xev-notes

Evernote access for AI agents. Search, read, create, and update notes from Claude Code, Cursor, Codex CLI, or any tool that can run bash commands.

## Why

Evernote no longer issues new API keys. This project uses Make.com as an authorized bridge to the Evernote API, with a bash CLI that handles all the logic.

## Quick Start

### 1. Install

```bash
git clone https://github.com/yaniv-golan/xev-notes.git
cd evernote-mcp
```

Requirements: `bash 3.2+`, `curl`, `jq`, `pandoc` (for write operations)

### 2. Set Up Make.com

```bash
./xev-cli/bin/xev-cli config setup --auto
```

This creates 6 Make.com scenarios via their API. You'll need a [Make.com](https://www.make.com) Core plan and an API token.

After the script finishes, open Make.com and:
1. Connect your Evernote account in each scenario
2. Activate each scenario

See [docs/make-com-setup.md](docs/make-com-setup.md) for detailed instructions.

### 3. Use

```bash
# Search notes
./xev-cli/bin/xev-cli search "quarterly review" --output human

# Read a note
./xev-cli/bin/xev-cli get <note-id> --format markdown

# List notebooks
./xev-cli/bin/xev-cli notebooks --output human

# Create a note
./xev-cli/bin/xev-cli create --title "Meeting Notes" --notebook "Work" --content "# Notes..."

# Update a note
./xev-cli/bin/xev-cli update <note-id> --append --content "Added later"
```

## AI Agent Integration

### Claude Code / Claude Desktop

Install as a plugin:

```
/install-plugin https://github.com/yaniv-golan/xev-notes
```

Then ask Claude: *"Search my Evernote for meeting notes about Q4 planning"*

### Cursor

Copy `.cursor-plugin/` to your project. The skill teaches Cursor how to use xev-cli.

### Codex CLI

The OpenAI agent config is at `skills/xev-evernote/agents/openai.yaml`.

## Architecture

```
AI Agent (Claude, Cursor, Codex)
  │
  ▼
xev-cli (bash) ── search, get, create, update, append
  │                ENML↔markdown conversion, error handling
  │
  ▼ HTTPS
Make.com Scenarios (6 webhooks)
  │                Authorized Evernote connector
  │
  ▼ Evernote Cloud API
Evernote
```

## Commands

| Command | Description |
|---------|-------------|
| `search <query>` | Search notes. Supports [Evernote search grammar](skills/xev-evernote/references/search-grammar.md) |
| `get <note-id>` | Get a note in markdown, text, or ENML format |
| `notebooks` | List all notebooks |
| `create` | Create a new note (markdown content, auto-converted to ENML) |
| `update <note-id>` | Replace or append content |
| `config` | Setup, show, check, or print config path |

All commands output structured JSON. Use `--output human` for readable output.

## Project Structure

```
xev-cli/              CLI source (bash)
  bin/xev-cli          Entry point
  lib/                 Modules: config, webhook, convert, output, progress, commands
  test/                Test suite
make/blueprints/       Make.com scenario templates (importable)
skills/xev-evernote/   AI agent skill definition
  SKILL.md             Skill instructions
  references/          CLI reference, error codes, search grammar
docs/                  Setup guide
```

## License

MIT
