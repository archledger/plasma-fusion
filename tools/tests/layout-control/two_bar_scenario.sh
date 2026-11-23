#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# Sourced by scenario-bridge.sh in two-bar seeds only, right after the holder's first preparation
# is accepted on its own output and while its popup is still open. The caller keeps the cleanup
# helper's ownership of the shell, and its own app; this scenario starts and quits a second app,
# which the container's teardown removes if the case fails. It opens that app on the other bar's
# output, has that bar prepare while the holder holds the slot, removes the holder's bar while the
# other bar's popup is still open and has the other bar prepare again.
set -euo pipefail

# These are native session actions, so also require a real private container.
[[ ${PFV:-} == /var/tmp/pfv-layout-control-* && ${HOME:-} == "$PFV/home" &&
   ${XDG_RUNTIME_DIR:-} == "$PFV/run" && ${PF_LAYOUT_PRIVATE_CONTAINER:-} == 1 &&
   -f /run/.containerenv ]] || {
  echo "Refusing a non-private two-bar scenario" >&2
  return 64
}
: "${OUT:?private output}" "${focus_boot:?target prelude}"

two_bar_helper="$HOME/.local/lib/layout-control/two_bar.py"
two_bar_mark() { python3 "$two_bar_helper" mark "$OUT" "$1" >/dev/null; }
two_bar_subject() {
  python3 -c 'import json, sys
json.dump({"schema": 1, "boot": sys.argv[2]}, open(sys.argv[1], "x"))' \
    "$OUT/two-bar-subject-$1.json" "$2"
}
# Each step's checker replays every native verdict and received frame up to its confirmation.
two_bar_wait() {
  local step=$1
  for _ in {1..100}; do
    if python3 "$two_bar_helper" step "$OUT" "$step" >/dev/null \
      2>>"$OUT/two-bar-$step-wait.log"; then
      return 0
    fi
    sleep 0.1
  done
  echo "FAIL: two-bar $step evidence not confirmed" >&2
  return 1
}
# The provider's latest recorded frame centre of an app: "x y".
two_bar_center() {
  python3 - "$OUT/kwin.log" "$1" <<'PY'
import json, sys
rows = [json.loads(line.split("layout-probe-focus ", 1)[1]) for line in open(sys.argv[1])
        if line.endswith("\n") and "layout-probe-focus " in line]
point = [row for row in rows if row["rememberedClass"] == sys.argv[2]
         and row["rememberedCenter"]][-1]["rememberedCenter"]
print(int(point["x"]), int(point["y"]))
PY
}

# The other bar's consumer: the one with control reports that is not the holder.
python3 - "$OUT/plasmashell.log" "$focus_boot" >"$OUT/two-bar-other.txt" <<'PY'
import json, sys
boots = set()
for line in open(sys.argv[1]):
    if line.endswith("\n") and "layout-probe-focus-control " in line:
        boots.add(json.loads(line.split("layout-probe-focus-control ", 1)[1])["boot"])
others = sorted(boots - {sys.argv[2]})
assert len(others) == 1, boots
print(others[0])
PY
read -r other_boot <"$OUT/two-bar-other.txt"

# 1. Two bars, one per output, each consumer bound to its own view; the holder's preparation was
#    accepted just before this case began.
two_bar_subject holder "$focus_boot"
two_bar_subject other "$other_boot"
two_bar_wait bars

# The other bar's control point, read once the checker has confirmed the bars' outputs, and a
# point on the desktop below it, on that bar's output: "x y x y".
python3 - "$OUT/plasmashell.log" "$focus_boot" "$other_boot" \
  >"$OUT/two-bar-other-control.txt" <<'PY'
import json, sys
latest = {}
for line in open(sys.argv[1]):
    if line.endswith("\n") and "layout-probe-focus-control " in line:
        row = json.loads(line.split("layout-probe-focus-control ", 1)[1])
        latest[row["boot"]] = row
holder, other = latest[sys.argv[2]], latest[sys.argv[3]]
assert other["screen"] and other["screen"] != holder["screen"], (holder, other)
print(int(other["x"]), int(other["y"]), int(other["x"]), int(other["y"]) + 400)
PY
read -r other_x other_y desktop_x desktop_y <"$OUT/two-bar-other-control.txt"

# 2. The holder's popup closes; a second app opens on the other bar's output.
pfinput "key esc"
pfinput "click $desktop_x $desktop_y"
mkfifo "$OUT/two-bar-beta.in"
exec {beta_input}<>"$OUT/two-bar-beta.in"
python3 "$HOME/.local/lib/layout-control/heldclient.py" pf.focus.beta 430x310 \
  <"$OUT/two-bar-beta.in" >"$OUT/two-bar-beta.log" 2>&1 &
beta_client=$!
wait_target_context "$other_boot" pf.focus.beta

# 3. A competing request from the other bar while the holder holds the one slot.
pfinput "click $other_x $other_y"
wait_target_popup pf.focus.beta
two_bar_mark competitor
pfinput "key space"
two_bar_wait competitor

# 4. With that popup still open, the holder's bar goes, found by its consumer. The mark follows the
#    removal, once the provider reader's own walk no longer lists the holder, so every read started
#    after the mark reads an inventory without it. A wake-up then makes the provider read. The
#    refused request's view is still current, so a provider that evaluated the refusal again and
#    prepared it afresh could grant it now that the slot is free.
python3 - "$focus_boot" >"$OUT/two-bar-remove.js" <<'PY'
import json, sys
print("var holder_boot=" + json.dumps(sys.argv[1]) + ";")
print("""
var holder=null;
panels().forEach(function(p){p.widgets('org.plasmafusion.layoutprobe').forEach(function(w){
    w.currentConfigGroup=['General'];
    if (JSON.parse(w.readConfig('layoutRequest','{}')).consumer===holder_boot) holder=p;
});});
if (!holder) throw new Error('the holder bar was not found');
var removed=holder.id;
holder.remove();
// The provider's reader walks the same lists, so neither the panel nor the holder's widget may
// still be there.
var listed=false;
panels().forEach(function(p){
    if (p.id===removed) listed=true;
    p.widgets('org.plasmafusion.layoutprobe').forEach(function(w){
        w.currentConfigGroup=['General'];
        if (JSON.parse(w.readConfig('layoutRequest','{}')).consumer===holder_boot) listed=true;
    });
});
print(JSON.stringify({removed:removed,listed:listed}));
""")
PY
evaljs "$OUT/two-bar-remove.js" >"$OUT/two-bar-removed.json"
grep -q -x '{"removed":[0-9]*,"listed":false}' "$OUT/two-bar-removed.json" || {
  echo "FAIL: the holder's bar is still listed after its removal" >&2
  return 1
}
two_bar_mark retired
qdbus org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component.invokeShortcut \
  "Plasma Fusion: Layout Probe Wake"
two_bar_wait retired
pfinput "key esc"

# 5. A new explicit request from the other bar, from a menu opened from its own app.
read -r beta_x beta_y < <(two_bar_center pf.focus.beta)
pfinput "click $beta_x $beta_y"
wait_target_context "$other_boot" pf.focus.beta
pfinput "click $other_x $other_y"
wait_target_popup pf.focus.beta
two_bar_mark explicit
pfinput "key space"
two_bar_wait explicit
pfinput "key esc"
printf 'quit\n' >&"$beta_input"
wait "$beta_client"
exec {beta_input}>&-

# The checker recomputes every step record from the raw logs before it writes the receipt.
python3 "$two_bar_helper" receipt "$OUT"
echo "PASS: two bars keep their own views; one slot, busy refusal and explicit recovery"
