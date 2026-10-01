#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# The shared QML blocks in packages/common/ (FusionMetrics, Motion, FusionTablet, FusionBackdrop,
# FusionAccent, FusionIconTile, FusionShadow, ...) for the tools/build.d scripts that stage QML
# packages. A package never carries its own copy of a block; the build copies each block the
# package uses.
#
#   shared-qml.sh check SRC LABEL
#       Fail when the package source SRC holds a file named like a shared block (or
#       FusionIconNames.js): the block would shadow, or be shadowed by, the shared one.
#   shared-qml.sh install SRC DEST
#       Copy FusionMetrics.qml (always, as before) and every other block that the .qml/.js files
#       under SRC use into DEST (one QML directory of the staged package), including blocks that
#       those blocks use. With FusionIconTile.qml it also writes FusionIconNames.js there; with
#       FusionShadow.qml it adds shaders/fusionshadow.frag.qsb (compiled from
#       packages/common/shaders/fusionshadow.frag when Qt's qsb is installed, else the compiled
#       file kept in the repository).
#   shared-qml.sh list SRC
#       Print the blocks SRC uses, one file name per line (FusionMetrics.qml first).
#   shared-qml.sh names OUTFILE
#       Write FusionIconNames.js: the app icon names that the Plasma Fusion icon theme draws as
#       tiles (generators/icons/names.py, APPS), for FusionIconTile.
#
# A package "uses" a block when its QML declares one (`Motion {`), types a property with it
# (`property FusionTablet tabletState`), casts to it (`as FusionAccent`) or names its file
# (`"FusionBackdrop.qml"`). ROOT is the repository root (tools/build.sh exports it).
set -euo pipefail

ROOT=${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}
COMMON=$ROOT/packages/common
NAMES_JS=FusionIconNames.js

die() { echo "shared-qml: $*" >&2; exit 1; }

# Names of the shared blocks (file names without .qml), FusionMetrics first.
blocks() {
  local f
  echo FusionMetrics
  for f in "$COMMON"/*.qml; do
    f=$(basename "$f" .qml)
    [ "$f" = FusionMetrics ] || echo "$f"
  done
}

# needed SRC: the blocks that the .qml/.js files under SRC use (comments ignored), closed over
# the blocks' own uses; FusionMetrics first. One file name per line.
needed() {
  # shellcheck disable=SC2046  # one argument per block name
  python3 - "$1" "$COMMON" $(blocks) <<'PY'
import pathlib
import re
import sys

src, common, blocks = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), sys.argv[3:]


def code(text, blank_strings=False):
    """The text without // and /* */ comments; string literals are kept whole, or blanked
    (quotes kept, contents replaced by spaces) with blank_strings."""
    out, i, n, quote = [], 0, len(text), None
    while i < n:
        c = text[i]
        if quote:
            if c == quote:
                quote = None
                out.append(c)
            elif blank_strings:
                out.append("\n" if c == "\n" else " ")
                if c == "\\" and i + 1 < n:
                    out.append(" ")
                    i += 2
                    continue
            else:
                out.append(c)
                if c == "\\" and i + 1 < n:
                    out.append(text[i + 1])
                    i += 2
                    continue
        elif c in "\"'`":
            quote = c
            out.append(c)
        elif text.startswith("//", i):
            j = text.find("\n", i)
            i = n if j < 0 else j
            continue
        elif text.startswith("/*", i):
            j = text.find("*/", i + 2)
            i = n if j < 0 else j + 2
            continue
        else:
            out.append(c)
        i += 1
    return "".join(out)


def patterns(t):
    """(pattern for code with blanked strings, pattern for code with strings)"""
    b = r"(?:^|[^\w.])"
    decl = re.compile("|".join([
        b + t + r"\s*\{",                         # Motion {
        r"\bproperty\s+(?:list<)?" + t + r"[\s>]",  # property FusionTablet tabletState
        r"\bas\s+" + t + r"\b",                   # x as FusionAccent
    ]), re.M)
    return decl, re.compile(r"(?:^|[^\w])" + t + r"\.qml\b")  # "FusionBackdrop.qml"


def texts(paths):
    for p in paths:
        try:
            text = p.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        yield code(text, blank_strings=True), code(text)


def used(t, sources):
    decl, fname = pats[t]
    return any(decl.search(bare) or fname.search(full) for bare, full in sources)


pats = {t: patterns(t) for t in blocks}
files = [p for p in src.rglob("*") if p.suffix in (".qml", ".js") and p.is_file()]
have = {"FusionMetrics"}
sources = list(texts(files))
have |= {t for t in blocks if used(t, sources)}
while True:
    own = list(texts(common / (b + ".qml") for b in sorted(have)))
    more = {t for t in blocks if t not in have and used(t, own)}
    if not more:
        break
    have |= more
for t in blocks:
    if t in have:
        print(t + ".qml")
PY
}

write_names() {
  local out=$1
  python3 - "$ROOT/generators/icons" "$out" <<'PY'
import json
import sys
sys.path.insert(0, sys.argv[1])
from names import APPS  # noqa: E402

names = sorted({n for group in APPS.values() for n in group})
if not names:
    sys.exit("shared-qml: generators/icons/names.py has no app icon names")
body = ",\n".join("    " + json.dumps(n) for n in names)
text = f"""// Generated by tools/build-lib/shared-qml.sh from generators/icons/names.py (APPS); do not edit.
// The app icon names that the Plasma Fusion icon theme draws as tiles ({len(names)} names).
.pragma library

const names = new Set([
{body}
]);

// True when the icon theme answers NAME with a Fusion tile: the name itself, or a shorter
// name after cutting "-suffix" parts, as the icon loader falls back ("google-chrome-canary").
function covers(name) {{
    let n = String(name || "");
    while (n !== "") {{
        if (names.has(n)) {{
            return true;
        }}
        const cut = n.lastIndexOf("-");
        if (cut <= 0) {{
            return false;
        }}
        n = n.substring(0, cut);
    }}
    return false;
}}
"""
with open(sys.argv[2], "w", encoding="utf-8") as f:
    f.write(text)
PY
}

# install_shadow_shader DIR: FusionShadow's compiled shader into DIR, compiled from its source
# when qsb is installed (so the staged file always matches the source).
install_shadow_shader() {
  local dir=$1 qsb candidate
  mkdir -p "$dir"
  qsb=$(command -v qsb || true)
  for candidate in /usr/lib64/qt6/bin/qsb /usr/lib/qt6/bin/qsb; do
    [ -n "$qsb" ] || { [ -x "$candidate" ] && qsb=$candidate; }
  done
  if [ -n "$qsb" ]; then
    "$qsb" --qt6 -o "$dir/fusionshadow.frag.qsb" "$COMMON/shaders/fusionshadow.frag"
  else
    install -m 0644 "$COMMON/shaders/fusionshadow.frag.qsb" "$dir/fusionshadow.frag.qsb"
  fi
  chmod 0644 "$dir/fusionshadow.frag.qsb"
}

cmd=${1:-}
case "$cmd" in
  check)
    src=${2:?shared-qml.sh check SRC LABEL}; label=${3:-$src}
    [ -d "$src" ] || die "$label: no package at $src"
    for t in $(blocks) "${NAMES_JS%.js}"; do
      ext=.qml; [ "$t" = "${NAMES_JS%.js}" ] && ext=.js
      hit=$(find "$src" -name "$t$ext" -print -quit)
      [ -z "$hit" ] || die "$label: the package has its own $t$ext (${hit#"$src"/}); the build copies packages/common/$t.qml"
    done
    ;;
  install)
    src=${2:?shared-qml.sh install SRC DEST}; dest=${3:?shared-qml.sh install SRC DEST}
    [ -d "$src" ] || die "no package at $src"
    mkdir -p "$dest"
    # an assignment, so that a failing scan stops the build (set -e skips a `for ... in $(...)`)
    files=$(needed "$src")
    case "$files" in FusionMetrics.qml*) ;; *) die "could not work out the blocks $src uses" ;; esac
    for f in $files; do
      install -m 0644 "$COMMON/$f" "$dest/$f"
      if [ "$f" = FusionIconTile.qml ]; then
        write_names "$dest/$NAMES_JS"
        chmod 0644 "$dest/$NAMES_JS"
      fi
      if [ "$f" = FusionShadow.qml ]; then
        install_shadow_shader "$dest/shaders"
      fi
    done
    ;;
  list)
    src=${2:?shared-qml.sh list SRC}
    needed "$src"
    ;;
  names)
    write_names "${2:?shared-qml.sh names OUTFILE}"
    ;;
  *)
    echo "usage: shared-qml.sh check SRC LABEL | install SRC DEST | list SRC | names OUTFILE" >&2
    exit 2
    ;;
esac
