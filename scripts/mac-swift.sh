#!/usr/bin/env bash
# Run `swift <args>` in one of this repo's packages on Martin's Mac (SSH host alias `mac`), using the current worktree.
# Each worktree syncs to its own cache dir on the Mac, so parallel worktrees build side by side; uncommitted changes
# are included and no git checkout on the Mac is touched. Run from optiplex.
#
#   scripts/mac-swift.sh TrismegistusKit test
#   scripts/mac-swift.sh TrismegistusUI build
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
[[ $# -ge 2 ]] || { echo "usage: $0 <package-dir> <swift args...>" >&2; exit 2; }
pkg="$1"; shift
[[ $pkg =~ ^[A-Za-z0-9_-]+$ && -f $root/$pkg/Package.swift ]] || { echo "no Swift package at '$pkg'" >&2; exit 2; }
dest="Library/Caches/trismegistus-mac/$(basename "$root")"
ssh -o BatchMode=yes mac "mkdir -p '$dest'"
rsync -a --delete --exclude .build --exclude .swiftpm --exclude .git --exclude .DerivedData \
    --exclude 'App/*.xcodeproj' "$root/" "mac:$dest/"
args=$(printf '%q ' "$@")
ssh -o BatchMode=yes mac "cd '$dest/$pkg' && swift $args"
