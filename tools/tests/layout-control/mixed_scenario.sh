#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# Sourced after the owned target/retirement prelude; the caller retains child/cleanup ownership.
set -euo pipefail

[[ ${PFV:-} == /var/tmp/pfv-layout-control-* && ${HOME:-} == "$PFV/home" &&
   ${XDG_RUNTIME_DIR:-} == "$PFV/run" && ${PF_LAYOUT_PRIVATE_CONTAINER:-} == 1 ]] || {
  echo "Refusing a non-private mixed-lifetime scenario" >&2
  return 64
}
: "${OUT:?private output}" "${target_prepare_request:?target prelude}"
: "${backend_owner:?captured backend}" "${identity_name:?captured provider}"
: "${alpha_x:?recorded application center}" "${alpha_y:?recorded application center}"

mixed_helper="$HOME/.local/lib/layout-control/mixed_lifetime.py"
mixed_snapshot() {
  local label=$1 count=$2 phase=${3:-online}
  for _ in {1..40}; do
    evaljs - >"$OUT/mixed-$label-inventory.json" <<'JS'
var rows=[];
panels().forEach(function(p){p.widgets('org.plasmafusion.layoutprobe').forEach(function(w){
    w.currentConfigGroup=['General'];
    var request=null;
    try{request=JSON.parse(w.readConfig('layoutRequest','{}'));}catch(e){}
    rows.push({id:w.id,request:request});
});});
print(JSON.stringify(rows));
JS
    if python3 "$mixed_helper" snapshot "$OUT" "$OUT/mixed-$label-inventory.json" \
      "$phase" "$count" >"$OUT/mixed-$label.json" 2>>"$OUT/mixed-snapshot-wait.log"
    then
      return 0
    fi
    sleep 0.1
  done
  echo "FAIL: mixed $label did not confirm $phase memory" >&2
  return 1
}
cp "$OUT/target-observations-$target_prepare_request.json" "$OUT/mixed-retired-preparation.json"
mixed_snapshot before 1
python3 - "$OUT/mixed-before.json" >"$OUT/mixed-create.js" <<'PY'
import json, sys
survivor = json.load(open(sys.argv[1]))["widgets"][0]
print("var survivor=" + json.dumps(survivor) + ";")
print("""
var matches=[];
panels().forEach(function(p){p.widgets('org.plasmafusion.layoutprobe').forEach(function(w){
    w.currentConfigGroup=['General'];
    var q=JSON.parse(w.readConfig('layoutRequest','{}'));
    if(w.id===survivor.id && q.consumer===survivor.query.consumer)matches.push(p);
});});
if(matches.length!==1)throw new Error('mixed survivor is not unique');
var replacement=matches[0].addWidget('org.plasmafusion.layoutprobe');
print(JSON.stringify({id:replacement.id,survivorId:survivor.id}));
""")
PY
evaljs "$OUT/mixed-create.js" >"$OUT/mixed-created.json"
mixed_snapshot consumers 2
qdbus org.freedesktop.DBus /org/freedesktop/DBus \
  org.freedesktop.DBus.GetId >"$OUT/mixed-bus-before.txt"
qdbus org.freedesktop.DBus /org/freedesktop/DBus \
  org.freedesktop.DBus.GetNameOwner org.kde.plasmashell >"$OUT/mixed-shell-before.txt"
qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript \
  plasmafusion-layout-probe >"$OUT/mixed-unload.txt"
mixed_retired_held=true
for _ in {1..40}; do
  mixed_retired_held=$(qdbus org.freedesktop.DBus /org/freedesktop/DBus \
    org.freedesktop.DBus.NameHasOwner "$identity_name")
  [[ $mixed_retired_held == false ]] && break
  sleep 0.1
done
[[ $mixed_retired_held == false ]] || return 1
mixed_snapshot unknown 2 unknown
qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.loadDeclarativeScript \
  "$HOME/.local/share/kwin/scripts/plasmafusion-layout-probe/contents/ui/main.qml" \
  plasmafusion-layout-probe >"$OUT/mixed-reload-id.txt"
qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.start
mixed_snapshot reloaded 2
mixed_new_identity=$(python3 - "$OUT/mixed-reloaded.json" <<'PY'
import json, sys
print(json.load(open(sys.argv[1]))["widgets"][0]["observation"]["packet"]["identityName"])
PY
)
qdbus org.freedesktop.DBus /org/freedesktop/DBus \
  org.freedesktop.DBus.GetNameOwner "$mixed_new_identity" >"$OUT/mixed-new-owner.txt"
qdbus org.freedesktop.DBus /org/freedesktop/DBus \
  org.freedesktop.DBus.GetId >"$OUT/mixed-bus-after.txt"
qdbus org.freedesktop.DBus /org/freedesktop/DBus \
  org.freedesktop.DBus.GetNameOwner org.kde.KWin >"$OUT/mixed-backend-after.txt"
qdbus org.freedesktop.DBus /org/freedesktop/DBus \
  org.freedesktop.DBus.GetNameOwner org.kde.plasmashell >"$OUT/mixed-shell-after.txt"
python3 - "$OUT" "$backend_owner" "$identity_name" "$mixed_new_identity" \
  >"$OUT/mixed-owners.json" <<'PY'
import json, sys
from pathlib import Path
root = Path(sys.argv[1])
read = lambda name: (root / ("mixed-" + name + ".txt")).read_text().strip()
print(json.dumps({
    "busBefore": read("bus-before"), "busAfter": read("bus-after"),
    "backendBefore": sys.argv[2], "backendAfter": read("backend-after"),
    "shellBefore": read("shell-before"), "shellAfter": read("shell-after"),
    "retiredIdentity": sys.argv[3], "retiredHeld": False,
    "newIdentity": sys.argv[4], "newOwner": read("new-owner"),
}))
PY
python3 "$mixed_helper" frames "$OUT"
evaljs "$OUT/mixed-inject.js" >"$OUT/mixed-inject-count.txt"
[[ $(cat "$OUT/mixed-inject-count.txt") == 3 ]] || return 1
qdbus org.kde.kglobalaccel /component/kwin \
  org.kde.kglobalaccel.Component.invokeShortcut "Plasma Fusion: Layout Probe Wake"
mixed_ready=false
for _ in {1..40}; do
  if mixed_snapshot after-late 2 \
    && python3 "$mixed_helper" late "$OUT" 2>>"$OUT/mixed-late-wait.log"
  then
    mixed_ready=true
    break
  fi
  sleep 0.1
done
[[ $mixed_ready == true ]] || return 1
python3 - "$OUT" <<'PY'
import json, sys
from pathlib import Path
root = Path(sys.argv[1])
survivor = json.loads((root / "mixed-before.json").read_text())["widgets"][0]
current = [row for row in json.loads((root / "mixed-after-late.json").read_text())["widgets"]
           if row["id"] == survivor["id"]][0]
with (root / "mixed-replayed-request.json").open("x") as output:
    json.dump(survivor["query"], output)
for label, query in (("replay", survivor["query"]), ("restore", current["query"])):
    script = ("var id=" + json.dumps(survivor["id"])
              + ",boot=" + json.dumps(survivor["query"]["consumer"])
              + ",request=" + json.dumps(query) + ";var written=0;")
    script += """
panels().forEach(function(p){p.widgets('org.plasmafusion.layoutprobe').forEach(function(w){
    if(w.id===id){
        w.currentConfigGroup=['General'];
        if(JSON.parse(w.readConfig('layoutRequest','{}')).consumer!==boot)
            throw new Error('mixed survivor lifetime changed');
        w.writeConfig('layoutRequest',JSON.stringify(request));++written;
    }
});});print(written);
"""
    with (root / ("mixed-" + label + ".js")).open("x") as output:
        output.write(script)
PY
evaljs "$OUT/mixed-replay.js" >"$OUT/mixed-replay-count.txt"
[[ $(cat "$OUT/mixed-replay-count.txt") == 1 ]] || return 1
qdbus org.kde.kglobalaccel /component/kwin \
  org.kde.kglobalaccel.Component.invokeShortcut "Plasma Fusion: Layout Probe Wake"
mixed_ready=false
for _ in {1..40}; do
  if python3 "$mixed_helper" refusal "$OUT" 2>>"$OUT/mixed-refusal-wait.log"; then
    mixed_ready=true
    break
  fi
  sleep 0.1
done
[[ $mixed_ready == true ]] || return 1
# The replay was a labeled driver fault, not a new consumer send. Restore its query.
evaljs "$OUT/mixed-restore.js" >"$OUT/mixed-restore-count.txt"
[[ $(cat "$OUT/mixed-restore-count.txt") == 1 ]] || return 1
python3 "$mixed_helper" restored "$OUT"
qdbus org.kde.kglobalaccel /component/kwin \
  org.kde.kglobalaccel.Component.invokeShortcut "Plasma Fusion: Layout Probe Wake"
mixed_ready=false
for _ in {1..40}; do
  if mixed_snapshot after-replay 2 \
    && python3 "$mixed_helper" progress "$OUT" 2>>"$OUT/mixed-progress-wait.log"
  then
    mixed_ready=true
    break
  fi
  sleep 0.1
done
[[ $mixed_ready == true ]] || return 1
python3 - "$OUT/mixed-created.json" "$OUT/mixed-after-replay.json" \
  >"$OUT/mixed-replacement-control.txt" <<'PY'
import json, sys
created, snapshot = [json.load(open(path)) for path in sys.argv[1:]]
replacement = [row for row in snapshot["widgets"] if row["id"] == created["id"]][0]
control = replacement["control"]
assert control and control["x"] >= 0 and control["y"] >= 0
print(replacement["query"]["consumer"], control["x"], control["y"], replacement["query"]["request"])
PY
read -r mixed_boot mixed_x mixed_y mixed_previous <"$OUT/mixed-replacement-control.txt"
pfinput "click $alpha_x $alpha_y"
wait_target_context "$mixed_boot" pf.focus.alpha
pfinput "click $mixed_x $mixed_y"
wait_target_popup pf.focus.alpha
pfinput "key space"
wait_target_reply "$mixed_boot" prepare true "$mixed_previous" pf.focus.alpha \
  >"$OUT/mixed-explicit-request.txt"
mixed_snapshot final 2
python3 "$mixed_helper" check "$OUT"
printf '%s\n' '{"schema":1,"passed":true,' \
  '"checks":["roundtrip-native","consumer-replacement","provider-reload",' \
  '"late-frame-rejection","stale-intent-refusal","explicit-recovery"]}' \
  >"$OUT/mixed-lifetime-result.json"
shot mixed-explicit-recovery
