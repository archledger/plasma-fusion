# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Fuzzes how the keyboard keys tool (packages/keyboard/plasma-fusion-keyboard-keys) patches
# plasma-keyboard's symbols.qml, a file another package installs (docs/parts/ci.md, "Fuzzing"). An
# input is the file's text. Checked: no exception and no input slower than libFuzzer's -timeout (a
# pattern that backtracks exponentially; inputs stay below 4 KiB, too short for a quadratic one,
# which packages/keyboard/tests/patch_test.py times); either the reason the page was left alone, or
# a page with each of Esc, Tab and the four arrows once more than before, the row's trademark key
# once less, the semicolon key kept and two more long-press lists.
#   python3 fuzz/keyboard_keys_fuzzer.py [libFuzzer options] [corpus directory...]
import sys

import atheris

import load_tool

TOOL = "packages/keyboard/plasma-fusion-keyboard-keys"
tool = load_tool.load(TOOL, "plasma_fusion_keyboard_keys")
ADDED = ["key: Qt.Key_" + k for k in ("Escape", "Tab", "Left", "Down", "Up", "Right")]


def check(ok, what):
    if not ok:
        raise AssertionError(what)


def TestOneInput(data):
    text = data.decode("utf-8", "replace")
    new, why = tool.patch_symbols(text)
    if new is None:
        check(isinstance(why, str) and why, f"left alone without a reason: {why!r}")
        return
    check(why == "", f"patched with a reason: {why!r}")
    for key in ADDED:
        check(new.count(key) == text.count(key) + 1, f"{key} is not added once")
    check(new.count("key: 0x2122") == text.count("key: 0x2122") - 1, "the trademark key is not removed once")
    check(new.count("Qt.Key_Semicolon") == text.count("Qt.Key_Semicolon"), "the semicolon key is not kept")
    check(new.count("alternativeKeys:") == text.count("alternativeKeys:") + 2, "not two more long-press lists")


if __name__ == "__main__":
    atheris.Setup(sys.argv, TestOneInput)
    atheris.Fuzz()
