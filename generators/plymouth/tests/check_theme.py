#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Static checks of a built Plymouth theme directory (run by generators/plymouth/build.sh).

    check_theme.py THEME_DIR

* plasma-fusion.plymouth names the script plugin, the image dir and the script file;
* every image file named in the script exists, and every PNG is used;
* PNGs are 8-bit RGBA (what libply's PNG loader handles);
* the script's brackets balance outside strings and comments, it is UTF-8, uses only the
  string escapes plymouth's scanner knows, and has no member names with a dash;
* greeting/ (used by plymouth-install.sh, not installed) holds the renderer, its layout with an
  entry for every NNN-greeting.png, and the font;
* the installed part stays small (it is copied into every initramfs).
"""
import json
import os
import re
import sys

from PIL import Image

# The theme is copied into every initramfs (Fedora 44 on the test device: about 55 MB).
MAX_BYTES = 3_000_000
GREETING_FILES = {"greeting.py", "layout.json", "SpaceGrotesk-SemiBold.ttf", "OFL-SpaceGrotesk.txt"}


def fail(msg):
    print(f"check_theme: {msg}", file=sys.stderr)
    sys.exit(1)


def strip_code(src, strings=None):
    """Remove comments and string literals, keeping line structure; the literals' raw text is
    appended to `strings`."""
    out, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        if c == '"':
            i += 1
            start = i
            while i < n and src[i] != '"':
                if src[i] == "\\":
                    i += 1
                if src[i] == "\n":
                    fail("newline inside a string literal")
                i += 1
            if strings is not None:
                strings.append(src[start:i])
            i += 1
            out.append('""')
        elif src.startswith("//", i) or c == "#":
            while i < n and src[i] != "\n":
                i += 1
        elif src.startswith("/*", i):
            end = src.find("*/", i + 2)
            if end < 0:
                fail("unterminated /* comment")
            out.append("\n" * src.count("\n", i, end))
            i = end + 2
        else:
            out.append(c)
            i += 1
    return "".join(out)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    d = sys.argv[1]
    name = "plasma-fusion"
    theme = open(os.path.join(d, f"{name}.plymouth"), encoding="utf-8").read()
    for key in ("ModuleName=script", f"ImageDir=/usr/share/plymouth/themes/{name}",
                f"ScriptFile=/usr/share/plymouth/themes/{name}/{name}.script", "[script-env-vars]"):
        if key not in theme:
            fail(f"{name}.plymouth lacks {key}")
    raw = open(os.path.join(d, f"{name}.script"), "rb").read()
    try:
        src = raw.decode("utf-8")
    except UnicodeDecodeError:
        fail("script is not UTF-8")
    if "#@PF_DATA@" in src:
        fail("data marker not replaced")
    # The script scanner knows only the escapes \n \e \0 \" (and passes any other escaped
    # character through as itself: "\t" is "t").
    literals = []
    code = strip_code(src, literals)
    for lit in literals:
        for esc in re.findall(r"\\(.)", lit):
            if esc not in 'ne0"\\':
                fail(f"unsupported escape \\{esc} in a string literal")
    # "a.b-c" reads as a.b minus c: members with a dash must use the index form a["b-c"].
    bad = re.search(r"[A-Za-z_\]]\.[A-Za-z_][A-Za-z0-9_]*-[A-Za-z_]", code)
    if bad:
        fail(f"member name with a dash: {bad.group(0)!r} (write it as [\"...\"])")
    pairs = {")": "(", "]": "[", "}": "{"}
    stack = []
    for lineno, line in enumerate(code.split("\n"), 1):
        for c in line:
            if c in "([{":
                stack.append((c, lineno))
            elif c in pairs:
                if not stack or stack[-1][0] != pairs[c]:
                    fail(f"unbalanced {c} on line {lineno}")
                stack.pop()
    if stack:
        fail(f"unclosed {stack[-1][0]} from line {stack[-1][1]}")
    named = set(re.findall(r'"((?:[0-9]{3}-)?[a-z0-9-]+\.png)"', src))
    pngs = {f for f in os.listdir(d) if f.endswith(".png")}
    missing = named - pngs
    if missing:
        fail(f"missing images: {sorted(missing)[:5]}")
    unused = pngs - named
    if unused:
        fail(f"unused images: {sorted(unused)[:5]}")
    gdir = os.path.join(d, "greeting")
    if not os.path.isdir(gdir) or set(os.listdir(gdir)) != GREETING_FILES:
        fail(f"greeting/ must hold exactly {sorted(GREETING_FILES)}")
    layout = json.load(open(os.path.join(gdir, "layout.json"), encoding="utf-8"))
    if layout.get("font") not in GREETING_FILES:
        fail("greeting/layout.json names a font that is not there")
    greet = {e["file"] for e in layout["scales"]}
    if greet != {f for f in pngs if f.endswith("-greeting.png")} or not greet:
        fail("greeting/layout.json does not match the NNN-greeting.png images")
    for e in layout["scales"]:
        with Image.open(os.path.join(d, e["file"])) as im:
            if im.size != (e["w"], e["h"]):
                fail(f"{e['file']} is {im.size}, layout says {(e['w'], e['h'])}")
    total = 0
    for f in sorted(os.listdir(d)):
        p = os.path.join(d, f)
        if f == "greeting":
            continue
        total += os.path.getsize(p)
        if f.endswith(".png"):
            with Image.open(p) as im:
                if im.mode != "RGBA" or im.info.get("interlace"):
                    fail(f"{f}: mode {im.mode}, expected non-interlaced RGBA")
        elif f not in (f"{name}.plymouth", f"{name}.script"):
            fail(f"unexpected file {f}")
    if total > MAX_BYTES:
        fail(f"theme is {total} bytes (limit {MAX_BYTES})")
    print(f"check_theme: {len(pngs)} images, {total // 1024} KiB, script {len(raw) // 1024} KiB: ok")


if __name__ == "__main__":
    main()
