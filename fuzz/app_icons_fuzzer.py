# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Fuzzes what the familiar icon tool (packages/appicons/plasma-fusion-app-icons) reads from files
# other programs write (docs/parts/ci.md, "Fuzzing"). An input is a desktop file's path below an
# applications directory (the first line, bytes as in a file name) and the file's bytes (the rest),
# which also stand for plasmafusionrc. Checked: no exception; keys and values come stripped; a key
# seen twice keeps its first value; an icon only for a visible application; a per-app tile name has
# no "-", and a name the tool builds fits in a file name; the mode is familiar or designs.
#   python3 fuzz/app_icons_fuzzer.py [libFuzzer options] [corpus directory...]
import os, pathlib, sys

import atheris

import load_tool

TOOL = "packages/appicons/plasma-fusion-app-icons"
tool = load_tool.load(TOOL, "plasma_fusion_app_icons")
LATER = "\n[Desktop Entry]\nType=Link\nIcon=later\nNoDisplay=true\nHidden=true\n"


def check(ok, what):
    if not ok:
        raise AssertionError(what)


def built_name_fits(name):
    """A name the tool builds an icon for: its file and the temporary file fit in a file name."""
    if tool.fits(name):
        tmp = tool.theme_file(tool.THEMES[0], name).with_suffix(".svg.tmp")
        check(len(os.fsencode(tmp.name)) <= 255, f"{name!r} is built but {tmp.name!r} is too long")


def TestOneInput(data):
    name, _, body = data.partition(b"\n")
    text = body.decode("utf-8", "replace")   # what read_text(errors="replace") gives in a UTF-8 locale

    values = tool.parse_desktop_entry(text)
    for k, v in values.items():
        check(isinstance(k, str) and isinstance(v, str), f"{k!r}: {v!r} is not text")
        check(k == k.strip() and v == v.strip() and "=" not in k, f"{k!r}={v!r} is not stripped")
    again = tool.parse_desktop_entry(text + LATER)
    for k, v in values.items():
        check(again.get(k) == v, f"{k!r} did not keep its first value {v!r} (got {again.get(k)!r})")

    icon = tool.visible_icon(values)
    if icon is not None:
        check(icon and icon == values.get("Icon"), f"visible_icon gave {icon!r} for Icon={values.get('Icon')!r}")
        check(values.get("Type") == "Application" and "true" not in (values.get("NoDisplay"), values.get("Hidden")),
              f"an icon for an entry that is not a visible application: {values}")
        if "/" not in icon:
            built_name_fits(icon)

    # The desktop id: the path below the applications directory with "-" for "/" (desktop_entries),
    # without ".desktop" (the shell's app id, wanted()).
    rel = str(pathlib.PurePosixPath(os.fsdecode(name.replace(b"\0", b"")) or "x.desktop"))
    did = rel.replace("/", "-")
    did = did[:-len(".desktop")] if did.endswith(".desktop") else did
    tile = tool.app_tile_name(did)
    check(tile.startswith("plasmafusion_app.") and "-" not in tile, f"per-app tile name {tile!r}")
    built_name_fits(tile)

    mode = tool.parse_mode(text)
    check(mode in ("familiar", "designs"), f"mode {mode!r}")
    check(tool.parse_mode("[Icons]\nAppIcons=designs\n" + text) == "designs", "the first AppIcons= line did not count")


if __name__ == "__main__":
    atheris.Setup(sys.argv, TestOneInput)
    atheris.Fuzz()
