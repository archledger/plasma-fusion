#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""A fake `busctl --user [--json=short]` for copytext-unit.sh and restore-keys-unit.sh: the
kglobalaccel calls that fusion-config.sh and fusion-restore.sh make, against a JSON state file.
Test tooling only.

  copytext_fakebus.py STATE plain|json call org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel METHOD SIG ARGS...
  copytext_fakebus.py STATE plain call org.kde.kglobalaccel /component/NAME org.kde.kglobalaccel.Component shortcutNames
"""
import json
import sys

path, mode, verb = sys.argv[1], sys.argv[2], sys.argv[3]
args = sys.argv[4:]
state = json.load(open(path))
keys = state.setdefault("keys", {})
if verb == "call" and args[:1] == ["org.kde.kglobalaccel"] and args[1].startswith("/component/") \
        and args[2:4] == ["org.kde.kglobalaccel.Component", "shortcutNames"]:
    # the component's action names (registered ones and those holding a key), as busctl prints "as"
    comp = args[1][len("/component/"):]
    names = sorted({k.split("|")[1] for k in keys if k.split("|")[0] == comp}
                   - {u.split("|", 1)[1] for u in state.get("unregistered", []) if u.split("|")[0] == comp})
    print("as", len(names), " ".join('"%s"' % n for n in names))
    sys.exit(0)
if verb != "call" or args[:3] != ["org.kde.kglobalaccel", "/kglobalaccel", "org.kde.KGlobalAccel"]:
    sys.exit("fakebus: unexpected call " + " ".join(sys.argv[3:]))
method, rest = args[3], args[5:]
out = None
if method == "shortcut":            # as 4 comp action "" "" -> ai
    out = {"type": "ai", "data": [keys.get(rest[1] + "|" + rest[2], [])]}
elif method == "setForeignShortcut":  # asai 4 comp action "" "" N keys...
    n = int(rest[5])
    keys[rest[1] + "|" + rest[2]] = [int(k) for k in rest[6:6 + n]]
elif method == "setShortcut":       # asaiu 4 comp action name name N keys... flags -> ai
    n = int(rest[5])
    k = [int(x) for x in rest[6:6 + n]]
    keys[rest[1] + "|" + rest[2]] = k
    if int(rest[6 + n]) & 2:
        state.setdefault("present", []).append(rest[1] + "|" + rest[2])
    out = {"type": "ai", "data": [k]}
elif method == "doRegister":         # as 4 comp action name name
    state.setdefault("registered", []).append(rest[1] + "|" + rest[2])
elif method == "unregister":         # ss comp action
    state.setdefault("unregistered", []).append(rest[0] + "|" + rest[1])
elif method == "globalShortcutsByKey":  # (ai)(i) 4 key 0 0 0 0 -> a(ssssssaiai)
    key = int(rest[1])
    holders = [[k.split("|")[1], k.split("|")[1], k.split("|")[0], k.split("|")[0], "default", "default", v, []]
               for k, v in keys.items() if key in v]
    out = {"type": "a(ssssssaiai)", "data": [holders]}
else:
    sys.exit("fakebus: unknown method " + method)
json.dump(state, open(path, "w"))
if out is not None:
    if mode == "json":
        print(json.dumps(out))
    else:
        print(out["type"], len(out["data"][0]), " ".join(str(x) for x in out["data"][0]))
