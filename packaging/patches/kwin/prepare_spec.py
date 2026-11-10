#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Add the optional requestedGeometry backport to Fedora's supported KWin specs."""

import datetime
from pathlib import Path
import re
import sys

PATCHES = {
    "6.7.5": ("0001-window-expose-requested-geometry.patch",),
    "6.8.2": (
        "0001-window-expose-requested-geometry-6.8.2.patch",
        "0002-initialize-startup-flags-6.8.2.patch",
    ),
}


def prepare(text, version_release, today):
    match = re.fullmatch(r"(6\.7\.5|6\.8\.2)-([0-9]+)\.fc44", version_release)
    if not match:
        raise ValueError("only Fedora 44 KWin 6.7.5 and 6.8.2 source builds are supported")
    version, release = match.groups()
    patches = PATCHES[version]
    checks = (
        r"^Name:\s+kwin\s*$",
        rf"^Version:\s+{re.escape(version)}\s*$",
        rf"^Release:\s+{release}%\{{\?dist\}}\s*$",
        r"^%autosetup -p1\s*$",
        r"^%changelog\s*$",
    )
    for pattern in checks:
        if len(re.findall(pattern, text, re.MULTILINE)) != 1:
            raise ValueError(f"unsupported or mismatched spec: {pattern}")
    reserved = any(re.search(rf"^Patch0*{number}\s*:", text, re.MULTILINE)
                   for number in range(9001, 9001 + len(patches)))
    if reserved or any(name in text for names in PATCHES.values() for name in names):
        raise ValueError("the backport or one of its reserved patch tags is already present")
    patch_tags = "\n".join(f"Patch{number}: {name}" for number, name in enumerate(patches, 9001))
    # Keep Fedora's other patches and %prep intact; %autosetup applies this patch too.
    text = re.sub(
        r"^(Release:\s+" + release + r"%\{\?dist\})[ \t]*$",
        rf"\1.pf1\n\n# Plasma Fusion optional KWin patches\n{patch_tags}",
        text,
        count=1,
        flags=re.MULTILINE,
    )
    # Spell the RPM changelog date independently of the machine's locale.
    weekdays = ("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")
    months = ("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")
    date = f"{weekdays[today.weekday()]} {months[today.month - 1]} {today.day:02d} {today.year}"
    entry = (
        f"* {date} Wisbendji Fimerlus <archledger236@gmail.com> - {version_release}.pf1\n"
        "- Expose requestedGeometry to scripts (KDE MR !10225)\n"
    )
    if version == "6.8.2":
        entry += "- Initialize startup flags before their first read\n"
    return text.replace("%changelog\n", "%changelog\n" + entry + "\n", 1)


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: prepare_spec.py SPEC VERSION-RELEASE")
    path = Path(sys.argv[1])
    try:
        updated = prepare(path.read_text(), sys.argv[2], datetime.datetime.now(datetime.UTC).date())
    except ValueError as error:
        sys.exit(str(error))
    path.write_text(updated)


if __name__ == "__main__":
    main()
