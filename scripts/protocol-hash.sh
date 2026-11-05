#!/usr/bin/env bash
# Print the sha256 of a protocol dir's schema.json and of its examples set (every examples/**/*.json path and hash,
# in byte order). protocol/SOURCE holds this output for our copy; a contract test recomputes it.
#
#   scripts/protocol-hash.sh [protocol-dir]     default: this repo's protocol/
set -euo pipefail
dir="${1:-$(cd "$(dirname "$0")/.." && pwd)/protocol}"
sha() { if command -v sha256sum >/dev/null; then sha256sum "$@"; else shasum -a 256 "$@"; fi; }
cd "$dir"
echo "schema.json $(sha schema.json | cut -d' ' -f1)"
echo "terminal.schema.json $(sha terminal.schema.json | cut -d' ' -f1)"
echo "examples $(find examples -type f -name '*.json' | LC_ALL=C sort | while read -r f; do sha "$f"; done | sha | cut -d' ' -f1)"
