#!/usr/bin/env bash
set -uo pipefail
XEV_CLI="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../xev-cli/bin" && pwd)/xev-cli"
input="$(cat)"
title="$(echo "$input" | jq -r '.title')"
notebook="$(echo "$input" | jq -r '.notebook')"
content="$(echo "$input" | jq -r '.content // empty')"

args=(--title "$title" --notebook "$notebook")
[[ -n "$content" ]] && args+=(--content "$content")

"$XEV_CLI" create "${args[@]}" 2>/dev/null
