#!/usr/bin/env bash
# Run TrismegistusKit's tests natively on Martin's Mac over SSH (wrapper around scripts/mac-swift.sh, which syncs this
# worktree to its own cache dir on the Mac). Run from optiplex.
#
#   scripts/mac-test.sh              swift test
#   scripts/mac-test.sh build        swift build
set -euo pipefail
[[ $# -gt 0 ]] || set -- test
exec "$(dirname "$0")/mac-swift.sh" TrismegistusKit "$@"
