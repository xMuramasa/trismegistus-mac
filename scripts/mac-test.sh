#!/usr/bin/env bash
# Run TrismegistusKit's tests natively on Martin's Mac over SSH (host alias `mac` in ~/.ssh/config on optiplex).
# Copies the working tree (uncommitted changes included) to a cache dir on the Mac, so it never touches a git
# checkout there. Run from optiplex.
#
#   scripts/mac-test.sh              swift test
#   scripts/mac-test.sh build        swift build
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
dest="Library/Caches/trismegistus-mac-test"
[[ $# -gt 0 ]] || set -- test
ssh -o BatchMode=yes mac "mkdir -p '$dest'"
rsync -a --delete --exclude .build --exclude .swiftpm --exclude .git "$root/" "mac:$dest/"
args=$(printf '%q ' "$@")
ssh -o BatchMode=yes mac "cd '$dest/TrismegistusKit' && swift $args"
