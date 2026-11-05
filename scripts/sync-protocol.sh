#!/usr/bin/env bash
# Copy the protocol schema and examples from the trismegistus repo (the owner of the protocol).
set -euo pipefail
src="${1:-$HOME/Projects/trismegistus/protocol}"
dst="$(cd "$(dirname "$0")/.." && pwd)/protocol"
[ -f "$src/schema.json" ] || { echo "no schema at $src" >&2; exit 1; }
cp "$src/schema.json" "$src/terminal.schema.json" "$dst/"
rm -rf "$dst/examples"; cp -R "$src/examples" "$dst/examples"
commit=$(git -C "$src" rev-parse --short HEAD)
sed -i.bak -E "s/commit \`[0-9a-f]+\`/commit \`$commit\`/" "$dst/README.md" && rm -f "$dst/README.md.bak"
"$(dirname "$0")/protocol-hash.sh" "$dst" > "$dst/SOURCE"
echo "protocol synced from $src ($commit)"
