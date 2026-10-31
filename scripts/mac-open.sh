#!/usr/bin/env bash
# Runs ON THE MAC, in Martin's own Terminal (installed as ~/.local/bin/trismegistus-open by
# scripts/mac-build.sh --install): signs ~/Applications/Trismegistus.app with Martin's Personal Team if it isn't yet,
# then opens it.
#
# Why here: builds come over SSH, where the signing key can't be used (codesign: errSecInternalComponent), so
# mac-build.sh signs ad-hoc. A team signature keeps the Keychain "Always Allow" and the login item across builds;
# ad-hoc ones change with every build. Never the work team: only the certificate of $team is used.
set -euo pipefail
team=22GV3A4KF8
app="$HOME/Applications/Trismegistus.app"
check=false
[[ ${1-} == --check ]] && check=true  # print what it would do, sign and open nothing (works over SSH)
[[ -d $app ]] || { echo "no app at $app (build it first)" >&2; exit 1; }

team_of() { codesign -dv "$1" 2>&1 | awk -F= '/^TeamIdentifier=/{print $2}'; }

if [[ $(team_of "$app") != "$team" ]]; then
    # The Apple Development identity whose certificate's organizational unit is the team.
    identity=""
    certs=$(security find-certificate -a -Z -p)
    for sha in $(security find-identity -v -p codesigning | awk '/"Apple Development/ {print $2}'); do
        ou=$(awk -v s="$sha" '$0 ~ "SHA-1 hash: " s {f = 1; next} f && /BEGIN CERT/ {p = 1} p {print} p && /END CERT/ {exit}' \
                <<<"$certs" | openssl x509 -noout -subject -nameopt multiline 2>/dev/null |
             awk -F'= ' '/organizationalUnitName/ {print $2}')
        if [[ $ou == "$team" ]]; then identity=$sha; break; fi
    done
    [[ -n $identity ]] || {
        echo "no Apple Development certificate for team $team: Xcode > Settings > Accounts > Manage Certificates" >&2
        exit 1
    }
    if $check; then
        echo "would sign with identity ${identity:0:8}… (team $team); now signed by: $(team_of "$app")"
        exit 0
    fi
    if pgrep -x Trismegistus >/dev/null; then
        echo "quitting the running Trismegistus (an older build) first"
        pkill -x Trismegistus
        for _ in 1 2 3 4 5; do pgrep -x Trismegistus >/dev/null || break; sleep 1; done
    fi
    entitlements=$(mktemp)
    trap 'rm -f "$entitlements"' EXIT
    codesign -d --entitlements - --xml "$app" >"$entitlements"
    for lib in "$app"/Contents/MacOS/*.dylib; do
        if [[ -e $lib ]]; then codesign --force --sign "$identity" "$lib"; fi
    done
    codesign --force --sign "$identity" --entitlements "$entitlements" "$app"
    codesign --verify --deep --strict "$app"
    echo "signed with team $team"
elif $check; then
    echo "already signed with team $team"
    exit 0
fi
open "$app"
