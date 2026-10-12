#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Check a widget's settings page against its configuration keys.

Plasma's settings dialog passes every key of contents/config/main.xml to the page as cfg_<key>
and its default as cfg_<key>Default (a missing property logs "Setting initial properties
failed"), and on Apply it writes every declared cfg_ property back. A widget with several pages
(contents/config/config.qml) gets the same treatment on each one: the dialog shows one page at a
time (AppletConfiguration.qml in Plasma 6.7 replaces the page, after Apply or Discard when it
has changes), creates it with every key and default, and on Apply writes back the cfg_ properties
of that page only, including keys another page edits. For every page this checks that:
  - the page declares cfg_<key> and cfg_<key>Default for every key;
  - a key the page has no control for (a plain cfg_ property the page never sets, such as a key
    edited on another page) is refreshed from Plasmoid.configuration in saveConfig(), so Apply
    does not write back a value another page or part changed while the page was open.

  config_page_keys_test.py PACKAGE_DIR...
"""

import re
import sys
from pathlib import Path


def check(package):
    config = package / "contents/config/config.qml"
    # Pages with a literal source are the widget's own; a source bound to a model (the clock's
    # calendar provider pages) belongs to another package.
    pages = re.findall(r'source:\s*"([^"]+)"', config.read_text()) if config.is_file() else []
    if not pages:
        return [f"{package}: no settings page in {config}"]
    keys = re.findall(r'<entry name="([^"]+)"', (package / "contents/config/main.xml").read_text())
    problems = []
    for name in pages:
        problems += check_page(package / "contents/ui" / name, keys)
    return problems


def check_page(page, keys):
    problems = []
    text = page.read_text()
    declared = set(re.findall(r"\bproperty\s+(?:alias|[a-z]+)\s+cfg_(\w+)", text))
    for key in keys:
        for name in (key, key + "Default"):
            if name not in declared:
                problems.append(f"{page}: no cfg_{name} (the dialog warns)")
    match = re.search(r"function saveConfig\(\)[^{]*\{(.*?)\n    \}", text, re.S)
    save = match[1] if match else ""
    outside = text.replace(save, "") if save else text
    plain = re.findall(r"\bproperty\s+(?!alias)[a-z]+\s+cfg_(\w+)", text)
    for key in plain:
        if key.endswith("Default") or key not in keys:
            continue
        edited = re.search(r"\bcfg_%s\s*=[^=]" % re.escape(key), outside)
        refreshed = re.search(r"\bcfg_%s\s*=\s*(?:\w+\.)*config(?:uration)?\.%s\b" % (re.escape(key), re.escape(key)), save)
        if not edited and not refreshed:
            problems.append(f"{page}: cfg_{key} has no control and is not refreshed in saveConfig()")
    return problems


def main(argv):
    if len(argv) < 2:
        print(__doc__.strip().splitlines()[-1].strip(), file=sys.stderr)
        return 2
    problems = []
    for arg in argv[1:]:
        problems += check(Path(arg))
    for p in problems:
        print(p, file=sys.stderr)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
