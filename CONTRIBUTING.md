# Contributing

Thanks for your interest in contributing to xev-notes!

## Development Setup

1. Clone the repo: `git clone https://github.com/yaniv-golan/evernote-mcp.git`
2. Install dependencies: `bash 3.2+`, `curl`, `jq`, `pandoc`
3. Run tests: `bash xev-cli/test/run_tests.sh`

## Running Tests

```bash
bash xev-cli/test/run_tests.sh
```

Tests are self-contained and don't require Make.com or Evernote connectivity.

## Linting

```bash
shellcheck xev-cli/bin/xev-cli xev-cli/lib/*.sh xev-mcp/tools/*/tool.sh
```

## Making Changes

1. Create a branch: `git checkout -b feat/my-change`
2. Make your changes
3. Run tests and linting
4. Commit with a descriptive message
5. Open a PR against `main`

## PR Checklist

- [ ] Tests pass (`bash xev-cli/test/run_tests.sh`)
- [ ] ShellCheck passes on changed files
- [ ] MCP tool schemas validate (`jq -e '.name and .description and .inputSchema' xev-mcp/tools/*/tool.meta.json`)
- [ ] Version consistency if VERSION changed (`bash tools/bump-version.sh`)

## Architecture

- `xev-cli/lib/` — CLI modules. Each file has a single responsibility.
- `xev-mcp/tools/` — MCP wrappers. Each tool.sh is a thin wrapper around xev-cli.
- `make/blueprints/` — Make.com scenario templates. Must be sanitized (no personal IDs).
- `skills/` — AI agent skill definitions.

## Versioning

Version is in `VERSION`. Run `tools/bump-version.sh` to propagate to all manifests.
