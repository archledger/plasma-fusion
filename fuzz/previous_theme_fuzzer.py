# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Fuzzes what the "My previous desktop" generator (tools/device/previous-theme.py) reads from files
# other programs write (docs/parts/ci.md, "Fuzzing"): Plasma's and the user's KConfig files, a
# Global Theme's contents/defaults and its metadata.json. An input is four files separated by NUL
# bytes: the user's files (one text for every file the generator reads), the kdedefaults files (the
# same), the previous Global Theme's contents/defaults and its metadata.json. Checked: no exception;
# parsed keys and values are text, values stripped; a later value of a key wins; the package's defaults
# files, with the theme's name in their comment, read back as exactly the values the generator
# chose (a name cannot add keys).
#   python3 fuzz/previous_theme_fuzzer.py [libFuzzer options] [corpus directory...]
import sys

import atheris

import load_tool

TOOL = "tools/device/previous-theme.py"
tool = load_tool.load(TOOL, "previous_theme")
FILES = ("kdeglobals", "kwinrc", "ksplashrc", "plasmarc", "kcminputrc")
LNF = "org.example.desktop"


def check(ok, what):
    if not ok:
        raise AssertionError(what)


def parsed(text):
    out = tool.parse_kconfig_text(text)
    for (group, key), value in out.items():
        check(isinstance(group, str) and isinstance(key, str), f"{(group, key)!r} is not text")
        check("=" not in key, f"key {key!r} holds the separator")
        check(value is None or (isinstance(value, str) and value == value.strip() and len(value.splitlines()) <= 1),
              f"value {value!r} of {key!r}")
    # Read twice from the top-level group: the second copy sets the same values again.
    check(tool.parse_kconfig_text("[]\n" + text + "\n[]\n" + text) == out, "a later value of a key did not win")
    return out


def TestOneInput(data):
    parts = (data.split(b"\0", 3) + [b""] * 4)[:4]
    user, kdedefaults, package = (p.decode("utf-8", "replace") for p in parts[:3])   # as parse_kconfig reads
    try:
        name = tool.package_name(parts[3].decode("utf-8"), LNF)   # main() reads metadata.json as strict UTF-8
    except UnicodeDecodeError:
        name = LNF
    check(isinstance(name, str) and name and len(name.splitlines()) == 1, f"name {name!r}")

    # A Look whose files are the fuzzed texts (Look.__init__ reads them from a configuration
    # directory and the data directories; a file not given here reads as empty).
    look = tool.Look.__new__(tool.Look)
    look.config_dir = look.data = "/nonexistent"
    look.user = dict.fromkeys(FILES, parsed(user))
    look.kdedefaults = dict.fromkeys(FILES, parsed(kdedefaults))
    look.system, look.sysdirs = [], []
    look.lookandfeel, look.package = LNF, "/nonexistent/" + LNF
    look.pkg_defaults = tool.package_defaults(parsed(package))
    for (f, g, k), v in look.pkg_defaults.items():
        check("][" not in f and "][" not in g, f"package default {(f, g, k)!r}")

    defaults, layout = tool.build(look)
    comment = tool.defaults_comment(name, "2026-10-02", "/home/user/.local/state/plasma-fusion/backup-1")
    check(all(line.startswith("# ") for line in comment.splitlines()), f"comment {comment!r}")
    for entries in (defaults, layout):
        want = {(header, key): value for header, key, value, _src in entries}
        got = tool.parse_kconfig_text(tool.render(entries, comment))
        check(got == want, f"the package's defaults read back as {got}, not {want}")


if __name__ == "__main__":
    atheris.Setup(sys.argv, TestOneInput)
    atheris.Fuzz()
