#!/usr/bin/env bash
# Design-token guard (#33). Run from the repo root; exits non-zero when
#   (a) TrismegistusUI's Tokens.swift differs from what scripts/gen-tokens.py makes of design/tokens.json now, or
#   (b) a view under TrismegistusUI/Sources or App/Trismegistus writes a raw literal where a token belongs: paddings
#       and spacings, frame sizes, `.font(.system(size:`, `Color(hex:`, `lineWidth:`, `.opacity(0.x)`, corner and
#       shadow radii. 0 and ±1 (the hairline) are allowed. Skipped: the generated file, tests, `#Preview` blocks, and
#       the files and folders listed in scripts/token-allowlist.txt (one per line, from the repo root).
#   (c) any Swift source (tests included) still says `Theme.`: the old compatibility names are gone (#37).
#   (d) a Swift source outside Tokens.swift and the tests says `Palette.`: views use the `Ink` roles (#38).
#   (e) a view formats a time with `.dateTime` or a system time style (`time: .shortened`, `style: .time`): times
#       start from TrismegistusKit's `.clock`, the 24-hour clock in every region (a 12-hour region read 13:42 as 01:42).
#   (f) a view interpolates into a localized `Text("…\(…)")`: its numbers come out grouped by region (1.748 beside
#       1748 elsewhere); interpolated text is `Text(verbatim:)`.
#
#   scripts/check-tokens.sh            both checks
#   scripts/check-tokens.sh --all      (b) only, ignoring the allow-list: every literal left (the App/ inventory)
#
# ENDFIELD_PALETTE overrides the palette's path (default ~/Projects/endfield-dotfiles/theme/palette.json).
set -euo pipefail
[[ -f design/tokens.json && -f scripts/gen-tokens.py ]] || { echo "run from the repo root" >&2; exit 2; }
generated=TrismegistusUI/Sources/TrismegistusUI/Tokens.swift
status=0

if [[ ${1-} != --all ]]; then
    palette="${ENDFIELD_PALETTE:-$HOME/Projects/endfield-dotfiles/theme/palette.json}"
    [[ -f $palette ]] || { echo "palette not found: $palette (set ENDFIELD_PALETTE)" >&2; exit 2; }
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    python3 -I scripts/gen-tokens.py "$palette" design/tokens.json "$tmp/Tokens.swift" > /dev/null
    if ! diff -u "$generated" "$tmp/Tokens.swift"; then
        echo "stale: $generated (run scripts/gen-tokens.py $palette design/tokens.json)"
        status=1
    fi
    allowlist=scripts/token-allowlist.txt
else
    allowlist=/dev/null
fi

python3 -I - "$allowlist" "$generated" <<'EOF' || status=1
import pathlib, re, sys

allowed = [l.strip().rstrip("/") for l in open(sys.argv[1]) if l.strip() and not l.startswith("#")]
generated = sys.argv[2]
NUM = r"(-?\d+(?:\.\d+)?)"
# Each pattern captures the literal right after its label: `width: geo.size.width * 0.3` is maths, not a literal.
patterns = [
    ("padding", re.compile(r"\.padding\(\s*(?:\.\w+\s*,\s*|\[[^\]]*\]\s*,\s*)?" + NUM + r"\s*\)")),
    ("spacing", re.compile(r"\b(?:spacing|minLength):\s*" + NUM)),
    ("frame", re.compile(r"\b(?:min|max|ideal)?(?:[wW]idth|[hH]eight):\s*" + NUM), r"\.frame\("),
    ("font size", re.compile(r"\.font\(\.system\(size:\s*" + NUM)),
    ("hex colour", re.compile(r"Color\(hex:\s*(0x[0-9A-Fa-f]+)")),
    ("line width", re.compile(r"\blineWidth:\s*" + NUM)),
    ("opacity", re.compile(r"\.opacity\(\s*" + NUM + r"\s*\)")),
    ("radius", re.compile(r"(?:[cC]ornerRadius|[rR]adius):\s*" + NUM)),
]


def calls(line, opener):
    """The argument text of each `opener(...)` call on the line (nested parens included)."""
    for m in re.finditer(opener, line):
        depth, i = 1, m.end()
        while i < len(line) and depth:
            depth += {"(": 1, ")": -1}.get(line[i], 0)
            i += 1
        yield line[m.end():i]


found = 0
for path in sorted(p for top in ("App", "TrismegistusUI", "TrismegistusKit") for p in pathlib.Path(top).rglob("*.swift")
                   if ".build" not in p.parts):
    for n, line in enumerate(path.read_text().splitlines(), 1):
        if re.search(r"\bTheme\.", line.split("//")[0]):  # the removed compatibility names (#37)
            print(f"{path}:{n}: old Theme name: {line.strip()}")
            found += 1
for top in ("TrismegistusUI/Sources", "App/Trismegistus"):  # raw palette colours: views read the Ink roles (#38)
    for path in sorted(pathlib.Path(top).rglob("*.swift")):
        if str(path) == generated:
            continue
        for n, line in enumerate(path.read_text().splitlines(), 1):
            if re.search(r"\bPalette\.", line.split("//")[0]):
                print(f"{path}:{n}: raw palette colour, use an Ink role: {line.strip()}")
                found += 1
def code_part(line):
    """The line without its `//` comment; a `//` inside a string literal (`" // "`) stays."""
    quoted = False
    for i, c in enumerate(line):
        if c == '"' and (i == 0 or line[i - 1] != "\\"):
            quoted = not quoted
        elif not quoted and line.startswith("//", i):
            return line[:i]
    return line


formats = [  # (e) times on the app's clock, (f) interpolated text verbatim
    (re.compile(r"\.dateTime\b|\btime:\s*\.(?:shortened|standard|complete)\b|\bstyle:\s*\.time\b"),
     "time off the 24-hour clock, start from `.clock`"),
    (re.compile(r'\bText\("[^"]*\\\('), "localized Text with interpolation (numbers by region), use Text(verbatim:)"),
]
for top in ("TrismegistusUI/Sources", "App/Trismegistus"):
    for path in sorted(pathlib.Path(top).rglob("*.swift")):
        for n, line in enumerate(path.read_text().splitlines(), 1):
            code = code_part(line)
            for rx, why in formats:
                if rx.search(code):
                    print(f"{path}:{n}: {why}: {line.strip()}")
                    found += 1
for top in ("TrismegistusUI/Sources", "App/Trismegistus"):
    for path in sorted(pathlib.Path(top).rglob("*.swift")):
        p = str(path)
        if p == generated or any(p == a or p.startswith(a + "/") for a in allowed):
            continue
        for n, line in enumerate(path.read_text().splitlines(), 1):
            # shortcut: previews sit at the end of a file, so everything from the first `#Preview` on is skipped;
            # a preview in the middle of a file would hide the views after it.
            if line.lstrip().startswith("#Preview"):
                break
            code = line.split("//")[0]
            for kind, rx, *opener in patterns:
                for text in (calls(code, opener[0]) if opener else [code]):
                    for m in rx.finditer(text):
                        v = m.group(1)
                        if kind not in ("hex colour", "font size") and abs(float(v)) in (0, 1):
                            continue
                        print(f"{p}:{n}: {kind} {v}: {line.strip()}")
                        found += 1
if found:
    print(f"{found} found: each line says why (raw literals: use the tokens in Tokens.swift, design/tokens.json)")
    sys.exit(1)
EOF
exit $status
