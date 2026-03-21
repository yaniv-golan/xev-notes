#!/usr/bin/env bash
set -uo pipefail
input="$(cat)"
title="$(echo "$input" | jq -r '.title')"
notebook="$(echo "$input" | jq -r '.notebook')"
content="$(echo "$input" | jq -r '.content // empty')"

args=(--title "$title" --notebook "$notebook")
[[ -n "$content" ]] && args+=(--content "$content")

xev-cli create "${args[@]}" 2>/dev/null
