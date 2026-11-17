#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# Sourced ONLY by the existing isolated vsession harness. No host/session discovery.
set -euo pipefail

[[ ${PFV:-} == /var/tmp/pfv-layout-control-* &&
   ${HOME:-} == "$PFV/home" &&
   ${XDG_RUNTIME_DIR:-} == "$PFV/run" ]] || {
    echo "Refusing a non-probe HOME/runtime" >&2
    return 64
}

observations() {
    python3 - "$OUT/plasmashell.log" <<'PY'
import json, sys
latest = {}
with open(sys.argv[1]) as trace:
    for line in trace:
        if not line.endswith("\n") or "layout-probe-observation " not in line:
            continue
        observation = json.loads(line.split("layout-probe-observation ", 1)[1])
        latest[observation["boot"]] = observation
print(json.dumps([{"consumer": key, "observation": value} for key, value in latest.items()]))
PY
}

wait_for_phase() {
    local phase=$1
    for _ in {1..40}; do
        observations >"$OUT/observations-$phase.json"
        if python3 - "$OUT/observations-$phase.json" "$phase" <<'PY'
import json, sys
rows = json.load(open(sys.argv[1]))
assert len(rows) == 2, rows
assert all(row["observation"]["phase"] == sys.argv[2] for row in rows), rows
PY
        then
            return 0
        fi
        sleep 0.1
    done
    echo "FAIL: no confirmed $phase state for both probe widgets" >&2
    return 1
}

loaded=$(qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.isScriptLoaded plasmafusion-layout-probe)
[[ $loaded == true ]] || { echo "FAIL: real declarative probe not loaded" >&2; return 1; }
qdbus org.kde.kglobalaccel >"$OUT/shortcut-components.txt"
qdbus org.kde.kglobalaccel /component/kwin >"$OUT/kwin-shortcut-interface.txt"
qdbus org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component.shortcutNames \
    >"$OUT/kwin-shortcut-names.txt"

evaljs - >"$OUT/widgets-created.txt" <<'JS'
var p=new Panel;
p.location="top";
p.height=40;
var a=p.addWidget("org.plasmafusion.layoutprobe");
var b=p.addWidget("org.plasmafusion.layoutprobe");
print(JSON.stringify([a.id,b.id]));
JS
wait_for_phase online 2>"$OUT/online-wait.log"
python3 - "$OUT/observations-online.json" <<'PY'
import json, sys
rows = json.load(open(sys.argv[1]))
assert len({row["consumer"] for row in rows}) == 2
assert len({row["observation"]["boot"] for row in rows}) == 2
for row in rows:
    observation = row["observation"]
    packet = observation["packet"]
    assert packet["consumer"] == observation["boot"]
    assert packet["capable"] is True, packet
    assert packet["refusal"] == -1, packet
    assert packet["competingProviderRejected"] is True, packet
    assert len(packet["epoch"]) == 32, packet
print("PASS: real wake-up, two-widget correlation and native null-output refusal")
PY

qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript plasmafusion-layout-probe \
    >"$OUT/unload-result.txt"
wait_for_phase offline 2>"$OUT/offline-wait.log"
python3 - "$OUT/observations-online.json" "$OUT/observations-offline.json" <<'PY'
import json, sys
before = {row["consumer"]: row["observation"] for row in json.load(open(sys.argv[1]))}
after = {row["consumer"]: row["observation"] for row in json.load(open(sys.argv[2]))}
assert before.keys() == after.keys()
for key, current in after.items():
    assert current["boot"] == before[key]["boot"]
    assert current["epoch"] == before[key]["epoch"]
    assert current["revision"] > before[key]["revision"]
print("PASS: cached retirement publication reached both live widgets")
PY
printf '%s\n' '{"schema":1,"passed":true,"checks":["roundtrip-native","retirement"]}' \
    >"$OUT/layout-probe-result.json"
echo "PASS: first transport slice only; reload/restart/focus/late-reply qualification remains"
