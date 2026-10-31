#!/usr/bin/env bash
# Build the macOS app on Martin's Mac (SSH host alias `mac`) from the current worktree: sync the tree to this worktree's
# cache dir, `xcodegen generate` in App/, then `xcodebuild`. It never launches the app: Martin starts it.
#
#   scripts/mac-build.sh             compile check without signing; prints errors, warnings and the result
#   scripts/mac-build.sh --install   signed Debug build, copied to ~/Applications/Trismegistus.app (Hermes only;
#                                    signing over SSH needs access to the login keychain's signing key)
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
mode=check
[[ ${1-} == --install ]] && mode=install
[[ -f $root/App/project.yml ]] || { echo "App/project.yml is missing" >&2; exit 2; }
dest="Library/Caches/trismegistus-mac/$(basename "$root")"
ssh -o BatchMode=yes mac "mkdir -p '$dest'"
rsync -a --delete --exclude .build --exclude .swiftpm --exclude .git --exclude .DerivedData \
    --exclude 'App/*.xcodeproj' "$root/" "mac:$dest/"
ssh -o BatchMode=yes mac bash -s -- "$dest" "$mode" <<'EOF'
set -uo pipefail
dest=$1 mode=$2
cd "$HOME/$dest/App" || exit 2
"$HOME/.local/bin/xcodegen" generate --quiet || exit 2
log=$(mktemp)
if [[ $mode == install ]]; then signing=(-allowProvisioningUpdates); else signing=(CODE_SIGNING_ALLOWED=NO); fi
xcodebuild -project Trismegistus.xcodeproj -scheme Trismegistus -configuration Debug \
    -derivedDataPath "$HOME/$dest/.DerivedData" "${signing[@]}" build > "$log" 2>&1
status=$?
# Xcode's own notices (not about our sources) are dropped so "zero warnings" stays meaningful.
grep -E '(error|warning): ' "$log" | grep -v -E 'appintentsmetadataprocessor|^ld: warning: ignoring duplicate libraries' | sort -u
if [[ $status -ne 0 ]]; then
    echo "--- last 40 lines of xcodebuild output ---"; tail -40 "$log"; echo "BUILD FAILED"; rm -f "$log"; exit 1
fi
echo "BUILD SUCCEEDED"
rm -f "$log"
if [[ $mode == install ]]; then
    app="$HOME/$dest/.DerivedData/Build/Products/Debug/Trismegistus.app"
    mkdir -p "$HOME/Applications" && rm -rf "$HOME/Applications/Trismegistus.app" && cp -R "$app" "$HOME/Applications/"
    codesign --verify --deep --strict "$HOME/Applications/Trismegistus.app" && echo "installed: ~/Applications/Trismegistus.app"
fi
EOF
