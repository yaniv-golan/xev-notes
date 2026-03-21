#!/usr/bin/env bash
set -uo pipefail
XEV_CLI="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../xev-cli/bin" && pwd)/xev-cli"
"$XEV_CLI" notebooks --output json 2>/dev/null
