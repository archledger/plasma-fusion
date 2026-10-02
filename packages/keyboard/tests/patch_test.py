# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# How the keyboard keys tool patches plasma-keyboard's symbols.qml: the second page's row of rare
# symbols becomes Esc, Tab and the arrows at the row's indent, the symbols go to two long-press
# lists; a page without the row is left alone with a reason; a long run of spaces or tabs is turned
# down at once (the row's pattern once tried every start inside such a run: 5 s for 32 KiB, 14 s for
# 64 KiB; now milliseconds for 1 MiB). Standard library only.
# Usage: python3 patch_test.py <path to plasma-fusion-keyboard-keys>
import importlib.machinery, importlib.util, sys, time

sys.dont_write_bytecode = True   # no __pycache__ next to the tool in the source tree
loader = importlib.machinery.SourceFileLoader("keyboard_keys", sys.argv[1])
spec = importlib.util.spec_from_loader("keyboard_keys", loader)
tool = importlib.util.module_from_spec(spec)
loader.exec_module(tool)
fails = []


def key(code, text):
    return f"                Key {{\n                    key: {code}\n                    text: {text}\n                }}\n"


PAGE = ("KeyboardLayout {\n    KeyboardRow {\n" + key("Qt.Key_section", '"§"') + key(" Qt.Key_QuoteDbl", "'\"'")
        + "    }\n    KeyboardRow {\n" + key("0x2122", "'™'") + key("0x00AE", "'®'")
        + key("Qt.Key_guillemotleft", "'«'") + key("Qt.Key_guillemotright", "'»'")
        + key("Qt.Key_Semicolon", '";"') + key("0x201C", "'“'") + key("0x201D", "'”'") + "    }\n}\n")

new, why = tool.patch_symbols(PAGE)
if new is None:
    fails.append(f"the page was left alone: {why}")
else:
    for k in ("Escape", "Tab", "Left", "Down", "Up", "Right"):
        if new.count(f"                Key {{\n                    key: Qt.Key_{k}\n") != 1:
            fails.append(f"Qt.Key_{k} is not on the page once at the row's indent")
    for gone in ("0x2122", "0x00AE", "guillemotleft", "0x201C"):
        if gone in new:
            fails.append(f"{gone} is still a key of its own")
    if new.count("Qt.Key_Semicolon") != 1 or new.count("alternativeKeys:") != 2:
        fails.append("the semicolon key or the two long-press lists are missing")
new, why = tool.patch_symbols(PAGE.replace("0x2122", "0x2123"))
if new is not None or "row" not in why:
    fails.append(f"a page without the row was patched ({why!r})")

for name, text in (("spaces", " " * 32768), ("tabs", "\t" * 32768), ("both", " \t" * 16384)):
    start = time.monotonic()
    new, why = tool.patch_symbols(text)
    took = time.monotonic() - start
    if new is not None or took > 1:
        fails.append(f"32 KiB of {name}: {why!r} after {took:.1f} s")
        break

for f in fails:
    print("FAIL:", f, file=sys.stderr)
print("keyboard-keys patch: ok" if not fails else f"keyboard-keys patch: {len(fails)} failed")
sys.exit(1 if fails else 0)
