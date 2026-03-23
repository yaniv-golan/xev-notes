# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.3] - 2026-03-23

### Fixed
- SKILL.md: global flags (`--progress`, `--trace`) now correctly placed before subcommand
- SKILL.md: /tmp/xev-run.sh wrapper solves variable persistence across Bash calls
- SKILL.md: removed hardcoded user path, uses mounted folder scanning
- SKILL.md: inline search grammar reference and rate limit guidance
- SKILL.md: explicit instruction to read reference docs before use

## [0.2.2] - 2026-03-23

### Fixed
- SKILL.md: replaced `2>/dev/null` with `--progress never` to keep errors visible

## [0.2.1] - 2026-03-23

### Fixed
- Linux `stat` compatibility: try `stat -c %Y` (Linux) before `stat -f %m` (macOS)

## [0.2.0] - 2026-03-23

### Added
- Webhook auto-discovery via Make.com API (only needs `MAKE_API_KEY` + `MAKE_TEAM_ID`)
- `XEV_DOTENV_DIR` env var for loading .env from any directory
- Plugin hooks for Cowork/Desktop: SessionStart (PATH setup), PreToolUse (validation), guard-env-read
- Config file no longer required — auto-discovery backfills missing URLs

### Fixed
- `${2:-{}}` bash expansion bug corrupting JSON payloads
- GNU sed `\|` alternation breaking pipe unescape on Linux
- ENML `id` attribute stripping (Evernote rejects them)
- Append sends HTML fragment instead of full ENML envelope
- Discovery prefers hooks linked to active scenarios

## [0.1.0] - 2026-03-21

### Added
- xev-cli with 6 commands: search, get, notebooks, create, update, append
- ENML to markdown/text conversion via pandoc
- Make.com webhook integration with error handling and rate limit detection
- `config setup --auto` for automated Make.com scenario creation via API
- 6 Make.com blueprint templates (sanitized, importable)
- Claude Code skill plugin with marketplace support
- Cursor and Codex CLI manifests
- Setup guide with troubleshooting (`docs/make-com-setup.md`)
- CLI reference, error codes, and search grammar documentation
