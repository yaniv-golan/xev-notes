#!/usr/bin/env bash
set -uo pipefail
XEV_CLI="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../xev-cli/bin" && pwd)/xev-cli"
input="$(cat)"
query="$(echo "$input" | jq -r '.query')"
notebook="$(echo "$input" | jq -r '.notebook // empty')"
limit="$(echo "$input" | jq -r '.limit // 20')"

args=("$query" --limit "$limit" --output json)
[[ -n "$notebook" ]] && args+=(--notebook "$notebook")

"$XEV_CLI" search "${args[@]}" 2>/dev/null
