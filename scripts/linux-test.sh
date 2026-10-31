#!/usr/bin/env bash
# Build and test TrismegistusKit on Linux in the official Swift image (the Mac runs the same tests natively with
# scripts/mac-test.sh). Runs as the calling user so .build stays user-owned.
#
#   scripts/linux-test.sh            swift test
#   scripts/linux-test.sh build      swift build
#   scripts/linux-test.sh test --filter ContractTests
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
img="${SWIFT_IMAGE:-swift:6.3.2}"
[[ $# -gt 0 ]] || set -- test
exec docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp \
    -v "$root:/src" -w /src/TrismegistusKit "$img" swift "$@"
