#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# Sourced after the target prelude's first explicit preparation and validation; the caller
# retains child/cleanup ownership. It changes only this private session's outputs/activities.
set -euo pipefail

# This case drives kscreen-doctor and the activity manager, so also require a real container.
[[ ${PFV:-} == /var/tmp/pfv-layout-control-* && ${HOME:-} == "$PFV/home" &&
   ${XDG_RUNTIME_DIR:-} == "$PFV/run" && ${PF_LAYOUT_PRIVATE_CONTAINER:-} == 1 &&
   -f /run/.containerenv ]] || {
  echo "Refusing a non-private view-loss scenario" >&2
  return 64
}
: "${OUT:?private output}" "${focus_boot:?target prelude}" "${target_request:?target prelude}"

view_helper="$HOME/.local/lib/layout-control/view_loss.py"
view_mark() { python3 "$view_helper" mark "$OUT" "$1" >/dev/null; }
view_value() { python3 "$view_helper" value "$OUT" "$@"; }
view_inventory() {
  evaljs - >"$OUT/view-$1-inventory.json" <<'JS'
var rows=[];
panels().forEach(function(p){p.widgets('org.plasmafusion.layoutprobe').forEach(function(w){
    w.currentConfigGroup=['General'];
    var request=null;
    try{request=JSON.parse(w.readConfig('layoutRequest','{}'));}catch(e){}
    rows.push({id:w.id,request:request});
});});
print(JSON.stringify(rows));
JS
}
# A step's checker reads only the complete log lines since its mark; the inventory, when the
# step needs one, is re-read with each attempt so it belongs to the confirming attempt.
view_wait() {
  local step=$1 inventory=${2:-false}
  for _ in {1..60}; do
    [[ $inventory == false ]] || view_inventory "$step"
    if python3 "$view_helper" step "$OUT" "$step" >/dev/null 2>>"$OUT/view-$step-wait.log"; then
      return 0
    fi
    sleep 0.1
  done
  echo "FAIL: view-loss $step evidence not confirmed" >&2
  return 1
}
view_wake() {
  qdbus org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component.invokeShortcut \
    "Plasma Fusion: Layout Probe Wake"
}
view_activity() {
  [[ $(qdbus org.kde.ActivityManager /ActivityManager/Activities \
    org.kde.ActivityManager.Activities.SetCurrentActivity "$1") == true ]]
}
# The guarded consumer's latest control point on the captured output: "x y validateX validateY".
view_control() {
  python3 - "$OUT/plasmashell.log" "$focus_boot" "$1" <<'PY'
import json, sys
rows = [json.loads(line.split("layout-probe-focus-control ", 1)[1])
        for line in open(sys.argv[1])
        if line.endswith("\n") and "layout-probe-focus-control " in line]
row = [row for row in rows if row["boot"] == sys.argv[2]][-1]
assert row["screen"] == sys.argv[3], row
print(row["x"], row["y"], row["validateX"], row["validateY"])
PY
}
# Activate empty desktop first so the app click is a real activation, then the app itself.
# Helpers run directly, never inside $(...), so errexit still stops at the first failed step.
view_focus_app() {
  local step=$1 desktop_x desktop_y app_x app_y
  desktop_x=$(view_value "$step" desktopX)
  desktop_y=$(view_value "$step" desktopY)
  app_x=$(view_value "$step" x)
  app_y=$(view_value "$step" y)
  pfinput "click $desktop_x $desktop_y"
  pfinput "click $app_x $app_y"
  wait_target_context "$focus_boot" pf.focus.alpha
}
view_prepare() {
  local previous=$1 focus_x focus_y
  read -r focus_x focus_y _ _ < <(view_control "$view_output")
  pfinput "click $focus_x $focus_y"
  wait_target_popup pf.focus.alpha
  pfinput "key space"
  wait_target_reply "$focus_boot" prepare true "$previous" pf.focus.alpha \
    >"$OUT/view-prepared-after-$previous.txt"
}

view_mark start
view_wake
view_wait baseline true
[[ $(view_value baseline focusBoot) == "$focus_boot" &&
   $(view_value baseline envelope request) == "$target_request" ]] || {
  echo "FAIL: view-loss baseline does not describe the prelude's validation" >&2
  return 1
}
view_output=$(view_value baseline output)
view_home_activity=$(view_value baseline activity)

# The output holding the prepared app and both bars disappears, then a new object returns.
view_mark disable
kscreen-doctor "output.$view_output.disable" >"$OUT/view-disable.log" 2>&1
view_wait lost
view_mark evacuated
view_wake
view_wait evacuated
shot view-output-lost
view_mark enable
kscreen-doctor "output.$view_output.enable" >"$OUT/view-enable.log" 2>&1
view_wait returned
read -r _ _ validate_x validate_y < <(view_control "$view_output")
view_mark revalidate
pfinput "click $validate_x $validate_y"
view_wait revalidated true
shot view-output-returned

view_mark activity-add
view_away_activity=$(qdbus org.kde.ActivityManager /ActivityManager/Activities \
  org.kde.ActivityManager.Activities.AddActivity pf-view-loss)
[[ -n $view_away_activity && $view_away_activity != "$view_home_activity" ]] || return 1
view_wait activity-added
view_mark subject-a
view_wake
view_wait subject-a
view_mark recover-a
view_focus_app subject-a
view_previous=$(view_value revalidated request)
view_prepare "$view_previous"
view_prepared=$(cat "$OUT/view-prepared-after-$view_previous.txt")
pfinput "key space"
wait_target_reply "$focus_boot" validate true "$view_prepared" pf.focus.alpha >/dev/null
view_wait recovered true

# Leaving and returning to the activity cannot revive the new handle.
view_mark switch-b
view_activity "$view_away_activity"
view_wait activity-left
shot view-activity-away
view_mark switch-a
view_activity "$view_home_activity"
view_wait activity-returned
read -r _ _ validate_x validate_y < <(view_control "$view_output")
view_mark revalidate-a
pfinput "click $validate_x $validate_y"
view_wait revalidated-a true

# The same control on another activity cannot prepare the app left on the original one.
view_focus_app subject-a
view_mark switch-b2
view_activity "$view_away_activity"
view_wait activity-left-again
read -r focus_x focus_y _ _ < <(view_control "$view_output")
view_mark popup-b
pfinput "click $focus_x $focus_y"
view_wait popup-b
view_mark wrong-view
pfinput "key space"
view_wait wrong-view
shot view-wrong-activity-refused
pfinput "key esc"
view_mark switch-a2
view_activity "$view_home_activity"
view_wait activity-returned-again
view_mark subject-final
view_wake
view_wait subject-final
view_mark recover-final
view_focus_app subject-final
view_previous=$(view_value wrong-view request)
view_prepare "$view_previous"
view_wait final

# The checker recomputes every step and audits the run before it writes the receipt.
python3 "$view_helper" receipt "$OUT"
shot view-explicit-recovery
