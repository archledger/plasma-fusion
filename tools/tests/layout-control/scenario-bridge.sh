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

reload_probe() {
    local provider="$HOME/.local/share/kwin/scripts/plasmafusion-layout-probe/contents/ui/main.qml"
    local ready=false
    qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.loadDeclarativeScript \
        "$provider" plasmafusion-layout-probe >"$OUT/reload-script-id.txt"
    qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.start
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

drop_retirement_frame=$(kreadconfig6 --file "$HOME/.config/kwinrc" \
    --group Script-plasmafusion-layout-probe --key DropRetirementFrame --default false)
if [[ $drop_retirement_frame == true ]]; then
    cp "$OUT/observations-online.json" "$OUT/observations-initial.json"
    qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript plasmafusion-layout-probe \
        >"$OUT/unload-result.txt"
    identity_held=true
    for _ in {1..40}; do
        identity_held=$(qdbus org.freedesktop.DBus /org/freedesktop/DBus \
            org.freedesktop.DBus.NameHasOwner "$identity_name")
        [[ $identity_held == false ]] && break
        sleep 0.1
    done
    [[ $identity_held == false ]] || { echo "FAIL: quiet retirement kept its alias" >&2; return 1; }
    printf '%s\n' "$identity_held" >"$OUT/retired-identity-owned.txt"
    current_backend=$(qdbus org.freedesktop.DBus /org/freedesktop/DBus \
        org.freedesktop.DBus.GetNameOwner org.kde.KWin)
    [[ $current_backend == "$backend_owner" ]] || return 1
    printf '%s\n' "$current_backend" >"$OUT/silent-backend-owner.txt"
    wait_for_phase unknown 2>"$OUT/silent-loss-wait.log"
    python3 - "$OUT/observations-initial.json" "$OUT/observations-unknown.json" \
        "$OUT/kwin.log" "$OUT/plasmashell.log" <<'PY'
import json, sys
before = {row["consumer"]: row["observation"] for row in json.load(open(sys.argv[1]))}
after = {row["consumer"]: row["observation"] for row in json.load(open(sys.argv[2]))}
assert before.keys() == after.keys()
for boot, row in after.items():
    assert row["packet"] is None and row["epoch"] == "" and row["revision"] == -1, row
    assert row["request"] > before[boot]["packet"]["request"], row
assert open(sys.argv[3]).read().count("layout-probe: retirement frame deliberately dropped") == 1
frames = [json.loads(line.split("layout-probe-received ", 1)[1])
          for line in open(sys.argv[4]) if "layout-probe-received " in line]
assert not any(frame["status"] == "offline" for frame in frames)
print("PASS: both live receivers invalidate without a retirement frame; KWin remains unchanged")
PY
    reload_probe
    python3 - "$OUT/observations-initial.json" "$OUT/observations-reloaded.json" <<'PY'
import json, sys
before = {row["consumer"]: row["observation"] for row in json.load(open(sys.argv[1]))}
after = {row["consumer"]: row["observation"] for row in json.load(open(sys.argv[2]))}
assert before.keys() == after.keys()
for boot, row in after.items():
    assert row["epoch"] != before[boot]["epoch"]
    assert row["packet"]["request"] > before[boot]["packet"]["request"]
print("PASS: the same live receivers recover only with a fresh query and new provider epoch")
PY
    printf '%s\n' \
        '{"schema":1,"passed":true,' \
        '"checks":["roundtrip-native","silent-retirement","provider-reload"]}' \
        >"$OUT/silent-retirement-result.json"
    return 0
fi

cp "$OUT/observations-online.json" "$OUT/observations-initial.json"
qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript plasmafusion-layout-probe \
    >"$OUT/unload-result.txt"
wait_for_phase unknown 2>"$OUT/retirement-wait.log"
cp "$OUT/observations-unknown.json" "$OUT/observations-retired.json"
identity_held=$(qdbus org.freedesktop.DBus /org/freedesktop/DBus \
    org.freedesktop.DBus.NameHasOwner "$identity_name")
[[ $identity_held == false ]] || { echo "FAIL: retired alias still owned" >&2; return 1; }
printf '%s\n' "$identity_held" >"$OUT/retired-identity-owned.txt"
retirement_received=false
for _ in {1..40}; do
    if python3 - "$OUT/observations-initial.json" "$OUT/observations-retired.json" \
        "$OUT/plasmashell.log" 2>>"$OUT/offline-delivery-wait.log" <<'PY'
import json, sys
before = {row["consumer"]: row["observation"] for row in json.load(open(sys.argv[1]))}
after = {row["consumer"]: row["observation"] for row in json.load(open(sys.argv[2]))}
assert before.keys() == after.keys()
for boot, current in after.items():
    assert current["phase"] == "unknown" and current["packet"] is None
    assert current["epoch"] == "" and current["revision"] == -1
    assert current["request"] > before[boot]["packet"]["request"]
frames = [json.loads(line.split("layout-probe-received ", 1)[1])
          for line in open(sys.argv[3])
          if line.endswith("\n") and "layout-probe-received " in line]
offline = {frame["receiverBoot"]: frame for frame in frames if frame["status"] == "offline"}
assert offline.keys() == before.keys()
for boot, frame in offline.items():
    assert frame["consumer"] == boot, "retirement frame reached the wrong live receiver"
    assert frame["epoch"] == before[boot]["epoch"]
    assert frame["request"] == before[boot]["packet"]["request"]
    assert frame["revision"] > before[boot]["revision"]
print("PASS: cached retirement frame reached both live widgets, and withdrawal invalidated state")
PY
    then
        retirement_received=true
        break
    fi
    sleep 0.1
done
[[ $retirement_received == true ]] || { echo "FAIL: missing retirement delivery" >&2; return 1; }
printf '%s\n' '{"schema":1,"passed":true,"checks":["roundtrip-native","retirement"]}' \
    >"$OUT/layout-probe-result.json"
reload_probe
python3 - "$OUT/observations-initial.json" "$OUT/observations-reloaded.json" <<'PY'
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
    "$OUT/plasmashell.log" "$shell_owner" <<'PY'
import json, sys
before = {row["consumer"]: row["observation"] for row in json.load(open(sys.argv[1]))}
after = {row["consumer"]: row["observation"] for row in json.load(open(sys.argv[2]))}
assert before.keys() == after.keys()
for boot, row in after.items():
    old = before[boot]
    assert row["phase"] == "online" and row["epoch"] == old["epoch"]
    assert row["request"] == old["request"]
    assert row["packet"]["backendOwner"] == old["packet"]["backendOwner"]
    assert row["packet"]["identityName"] == old["packet"]["identityName"]
    # A queued legitimate reply may arrive; it must not be the injected high revision.
    assert old["revision"] <= row["revision"] < old["revision"] + 10000
trace = open(sys.argv[3]).read()
assert trace.count('layout-probe-rejected backend owner ') == 2
accepted = [json.loads(line.split("layout-probe-observation ", 1)[1])
            for line in trace.splitlines() if "layout-probe-observation " in line]
assert all(not row["packet"] or row["packet"]["backendOwner"] != sys.argv[4] for row in accepted)
print("PASS: wrong-backend high-revision frames rejected by both receivers")
PY
printf '%s\n' '{"schema":1,"aliasReleased":true,"staleBackendRejected":true}' \
    >"$OUT/identity-fence-result.json"

observations >"$OUT/observations-before-ordering.json"
python3 - "$OUT/observations-before-ordering.json" "$OUT/ordering-burst.js" \
    "$OUT/ordering-inputs.json" <<'PY'
import json, sys
rows = json.load(open(sys.argv[1]))
messages = []
expected = {}
for row in rows:
    packet = row["observation"]["packet"]
    base = packet["revision"]
    assert base < 2147483546, "burst would exceed the protocol's integer bound"
    expected[row["consumer"]] = {
        "low": base + 10, "high": base + 100, "middle": base + 90,
        "epoch": packet["epoch"], "request": packet["request"],
        "backendOwner": packet["backendOwner"], "identityName": packet["identityName"],
    }
    frames = [json.dumps(packet | {"revision": base + offset}) for offset in (10, 100, 90)]
    messages.append({"consumer": row["consumer"], "packets": frames})
with open(sys.argv[3], "w") as inputs:
    json.dump(expected, inputs)
with open(sys.argv[2], "w") as injection:
    injection.write("var messages=" + json.dumps(messages) + ";var written=0;"
        "panels().forEach(function(p){"
        "p.widgets('org.plasmafusion.layoutprobe').forEach(function(w){"
        "w.currentConfigGroup=['General'];var q=JSON.parse(w.readConfig('layoutRequest',''));"
        "messages.forEach(function(m){if(m.consumer===q.consumer){"
        "m.packets.forEach(function(packet){"
        "w.writeConfig('layoutResponse',packet);++written;});}});});});print(written);")
PY
evaljs "$OUT/ordering-burst.js" >"$OUT/ordering-burst-send.txt"
[[ $(cat "$OUT/ordering-burst-send.txt") == 6 ]] || return 1
python3 - "$OUT/ordering-inputs.json" "$OUT/plasmashell.log" <<'PY'
import json, sys
expected = json.load(open(sys.argv[1]))
lines = open(sys.argv[2]).readlines()
for boot, spec in expected.items():
    revisions = {spec[key] for key in ("low", "high", "middle")}
    received = {}
    accepted = []
    for index, line in enumerate(lines):
        if not line.endswith("\n"):
            continue
        if "layout-probe-received " in line:
            packet = json.loads(line.split("layout-probe-received ", 1)[1])
            if packet["receiverBoot"] == boot and packet["revision"] in revisions:
                assert packet["consumer"] == boot and packet["epoch"] == spec["epoch"]
                assert packet["request"] == spec["request"]
                received[packet["revision"]] = index
        if "layout-probe-observation " in line:
            row = json.loads(line.split("layout-probe-observation ", 1)[1])
            if row["boot"] == boot and row["packet"] and row["revision"] in revisions:
                accepted.append(index)
    assert received.keys() == revisions, "burst packets did not all reach the live receiver"
    assert not accepted or min(accepted) > max(received.values()), \
        "burst did not queue while verification was in flight"
print("PASS: all six burst frames reached the intended receivers before verification completed")
PY
ordered=false
for _ in {1..40}; do
    observations >"$OUT/observations-after-ordering.json"
    if python3 - "$OUT/ordering-inputs.json" "$OUT/observations-after-ordering.json" \
        2>>"$OUT/ordering-wait.log" <<'PY'
import json, sys
expected = json.load(open(sys.argv[1]))
after = {row["consumer"]: row["observation"] for row in json.load(open(sys.argv[2]))}
assert after.keys() == expected.keys()
for boot, row in after.items():
    spec = expected[boot]
    assert row["phase"] == "online" and row["revision"] == spec["high"], row
    assert row["packet"]["consumer"] == boot and row["epoch"] == spec["epoch"]
    assert row["packet"]["request"] == spec["request"]
    assert row["packet"]["backendOwner"] == spec["backendOwner"]
    assert row["packet"]["identityName"] == spec["identityName"]
PY
    then
        ordered=true
        break
    fi
    sleep 0.1
done
[[ $ordered == true ]] || { echo "FAIL: newer pending state was lost" >&2; return 1; }
printf '%s\n' '{"schema":1,"passed":true,' \
    '"checks":["roundtrip-native","same-provider-ordering"]}' >"$OUT/reply-ordering-result.json"
echo "PASS: same-provider ordering plus prior transport/lifetime checks; full G0 remains open"
