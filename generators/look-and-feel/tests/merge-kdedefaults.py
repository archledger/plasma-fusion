#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Test tooling (not installed): emulate startplasma's XDG_CONFIG_DIRS=~/.config/kdedefaults layer inside a
# virtual session that was not started by startplasma. For every key in kdedefaults/<file>
# that ~/.config/<file> does not set, write it with kwriteconfig6 (lower priority, like the
# cascade). Nested groups use KConfig's [a][b] syntax.
import os, re, subprocess, sys
home = os.path.expanduser("~")
dd = os.path.join(home, ".config", "kdedefaults")
def parse(path):
    groups = {}
    cur = None
    if not os.path.exists(path):
        return groups
    for line in open(path, encoding="utf-8", errors="replace"):
        line = line.rstrip("\n")
        if not line or line.startswith("#"):
            continue
        if line.startswith("["):
            cur = tuple(re.findall(r"\[([^\]]*)\]", line))
            groups.setdefault(cur, {})
            continue
        if "=" in line and cur is not None:
            k, v = line.split("=", 1)
            groups[cur][k] = v
    return groups
n = 0
only = set(sys.argv[1:])
for f in sorted(os.listdir(dd)) if os.path.isdir(dd) else []:
    if f == "package" or (only and f not in only):
        continue
    src = parse(os.path.join(dd, f))
    dst = parse(os.path.join(home, ".config", f))
    for g, kv in src.items():
        for k, v in kv.items():
            if k in dst.get(g, {}):
                continue
            cmd = ["kwriteconfig6", "--file", f]
            for part in g:
                cmd += ["--group", part]
            cmd += ["--key", k, v]
            subprocess.run(cmd, check=False)
            n += 1
            print("merged", f, g, k, "=", v)
print("merged", n, "keys")
