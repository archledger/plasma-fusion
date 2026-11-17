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
backend_owner=$(qdbus org.freedesktop.DBus /org/freedesktop/DBus \
    org.freedesktop.DBus.GetNameOwner org.kde.KWin)
python3 - "$OUT/observations-online.json" "$backend_owner" "$OUT/identity-name.txt" <<'PY'
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
    assert packet["backendOwner"] == sys.argv[2], packet
    assert packet["identityName"].startswith("org.plasmafusion.LayoutProbe.p"), packet
names = {row["observation"]["packet"]["identityName"] for row in rows}
assert len(names) == 1
with open(sys.argv[3], "w") as identity:
    identity.write(names.pop())
print("PASS: real wake-up, two-widget correlation and native null-output refusal")
PY
identity_name=$(cat "$OUT/identity-name.txt")
identity_owner=$(qdbus org.freedesktop.DBus /org/freedesktop/DBus \
    org.freedesktop.DBus.GetNameOwner "$identity_name")
[[ $identity_owner == "$backend_owner" ]] || return 1

qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript plasmafusion-layout-probe \
    >"$OUT/unload-result.txt"
wait_for_phase offline 2>"$OUT/offline-wait.log"
identity_held=$(qdbus org.freedesktop.DBus /org/freedesktop/DBus \
    org.freedesktop.DBus.NameHasOwner "$identity_name")
[[ $identity_held == false ]] || { echo "FAIL: retired alias still owned" >&2; return 1; }
printf '%s\n' "$identity_held" >"$OUT/retired-identity-owned.txt"
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
cp "$OUT/observations-online.json" "$OUT/observations-initial.json"

provider="$HOME/.local/share/kwin/scripts/plasmafusion-layout-probe/contents/ui/main.qml"
qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.loadDeclarativeScript \
    "$provider" plasmafusion-layout-probe >"$OUT/reload-script-id.txt"
qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.start
ready=false
for _ in {1..40}; do
    if python3 - "$OUT/kwin.log" <<'PY'
import sys
with open(sys.argv[1]) as trace:
    assert sum("layout-probe: initialized " in line for line in trace) == 2
PY
    then
        ready=true
        break
    fi
    sleep 0.1
done
[[ $ready == true ]] || { echo "FAIL: reloaded provider not initialized" >&2; return 1; }
qdbus org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component.invokeShortcut \
    "Plasma Fusion: Layout Probe Wake"
wait_for_phase online 2>"$OUT/reload-wait.log"
cp "$OUT/observations-online.json" "$OUT/observations-reloaded.json"
python3 - "$OUT/observations-offline.json" "$OUT/observations-reloaded.json" <<'PY'
import json, sys
before = {row["consumer"]: row["observation"] for row in json.load(open(sys.argv[1]))}
after = {row["consumer"]: row["observation"] for row in json.load(open(sys.argv[2]))}
assert before.keys() == after.keys()
for key, current in after.items():
    assert current["epoch"] != before[key]["epoch"]
    assert current["packet"]["request"] > before[key]["packet"]["request"]
    assert current["packet"]["capable"] is True
print("PASS: provider reload uses a fresh exchange and new epoch for both live receivers")
PY
printf '%s\n' '{"schema":1,"providerReload":true}' >"$OUT/reload-result.json"

shell_owner=$(qdbus org.freedesktop.DBus /org/freedesktop/DBus \
    org.freedesktop.DBus.GetNameOwner org.kde.plasmashell)
python3 - "$OUT/observations-reloaded.json" "$shell_owner" "$OUT/stale-backend.js" <<'PY'
import json, sys
rows = json.load(open(sys.argv[1]))
messages = []
for row in rows:
    packet = dict(row["observation"]["packet"])
    packet["backendOwner"] = sys.argv[2]
    packet["revision"] += 10000
    messages.append({"consumer": row["consumer"], "packet": json.dumps(packet)})
with open(sys.argv[3], "w") as injection:
    injection.write("var messages=" + json.dumps(messages) + ";"
        "panels().forEach(function(p){p.widgets('org.plasmafusion.layoutprobe').forEach(function(w){"
        "w.currentConfigGroup=['General'];var q=JSON.parse(w.readConfig('layoutRequest',''));"
        "messages.forEach(function(m){if(m.consumer===q.consumer){"
        "w.writeConfig('layoutResponse',m.packet);}});});});")
PY
evaljs "$OUT/stale-backend.js" >"$OUT/stale-backend-send.txt"
for _ in {1..40}; do
    observations >"$OUT/observations-after-stale-backend.json"
    if python3 - "$OUT/observations-after-stale-backend.json" "$OUT/plasmashell.log" "$shell_owner" <<'PY'
import json, sys
rows = json.load(open(sys.argv[1]))
trace = open(sys.argv[2]).read()
assert (all(row["observation"]["packet"]["backendOwner"] == sys.argv[3] for row in rows)
        or trace.count('layout-probe-rejected backend owner ') >= 2)
PY
    then
        break
    fi
    sleep 0.1
done
python3 - "$OUT/observations-reloaded.json" "$OUT/observations-after-stale-backend.json" \
    "$OUT/plasmashell.log" <<'PY'
import json, sys
before = {row["consumer"]: row["observation"] for row in json.load(open(sys.argv[1]))}
after = {row["consumer"]: row["observation"] for row in json.load(open(sys.argv[2]))}
assert before == after, "a frame from the wrong backend changed receiver state"
assert open(sys.argv[3]).read().count('layout-probe-rejected backend owner ') == 2
print("PASS: wrong-backend high-revision frames rejected by both receivers")
PY
printf '%s\n' '{"schema":1,"aliasReleased":true,"staleBackendRejected":true}' \
    >"$OUT/identity-fence-result.json"
echo "PASS: delivery, retirement, reload and identity fence; remaining G0 cases unqualified"
