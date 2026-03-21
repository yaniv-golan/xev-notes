#!/usr/bin/env bash
set -uo pipefail
input="$(cat)"
query="$(echo "$input" | jq -r '.query')"
notebook="$(echo "$input" | jq -r '.notebook // empty')"
limit="$(echo "$input" | jq -r '.limit // 20')"

args=("$query" --limit "$limit" --output json)
[[ -n "$notebook" ]] && args+=(--notebook "$notebook")

xev-cli search "${args[@]}" 2>/dev/null
