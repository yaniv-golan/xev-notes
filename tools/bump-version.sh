#!/usr/bin/env bash
# bump-version.sh — Propagate version from VERSION file to all manifests
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
V=$(cat "${REPO_ROOT}/VERSION" | tr -d '[:space:]')

echo "Bumping version to ${V}..."

# Plugin manifests
jq --arg v "$V" '.version = $v' "${REPO_ROOT}/.claude-plugin/plugin.json" > /tmp/pj.tmp && mv /tmp/pj.tmp "${REPO_ROOT}/.claude-plugin/plugin.json"
jq --arg v "$V" '.version = $v' "${REPO_ROOT}/.cursor-plugin/plugin.json" > /tmp/pj.tmp && mv /tmp/pj.tmp "${REPO_ROOT}/.cursor-plugin/plugin.json"

# SKILL.md frontmatter
sed -i.bak -E "s/version: \"[^\"]*\"/version: \"${V}\"/" "${REPO_ROOT}/skills/xev-evernote/SKILL.md"
rm -f "${REPO_ROOT}/skills/xev-evernote/SKILL.md.bak"

# Codex agent
sed -i.bak -E "s/version: \"[^\"]*\"/version: \"${V}\"/" "${REPO_ROOT}/skills/xev-evernote/agents/openai.yaml"
rm -f "${REPO_ROOT}/skills/xev-evernote/agents/openai.yaml.bak"

# xev-cli version
sed -i.bak -E "s/XEV_VERSION=\"[^\"]*\"/XEV_VERSION=\"${V}\"/" "${REPO_ROOT}/xev-cli/bin/xev-cli"
rm -f "${REPO_ROOT}/xev-cli/bin/xev-cli.bak"

echo "Done. Updated all files to version ${V}."
echo "Files changed:"
git diff --name-only 2>/dev/null || true
