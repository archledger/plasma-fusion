#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# Sourced by scenario-bridge.sh in completion seeds only, right after the holder's first
# preparation is accepted and while its popup is still open; the caller retains child/cleanup
# ownership. Its actions cause newer state frames for decided preparations; the only requests
# it adds are the competitor's and the holder's explicit preparations.
set -euo pipefail

# These are native session actions, so also require a real private container.
[[ ${PFV:-} == /var/tmp/pfv-layout-control-* && ${HOME:-} == "$PFV/home" &&
   ${XDG_RUNTIME_DIR:-} == "$PFV/run" && ${PF_LAYOUT_PRIVATE_CONTAINER:-} == 1 &&
   -f /run/.containerenv ]] || {
  echo "Refusing a non-private completion scenario" >&2
  return 64
}
: "${OUT:?private output}" "${focus_boot:?target prelude}" "${focus_x:?target prelude}" \
  "${focus_y:?target prelude}"

completion_helper="$HOME/.local/lib/layout-control/completion.py"
completion_mark() { python3 "$completion_helper" mark "$OUT" "$1" >/dev/null; }
completion_subject() {
  python3 -c 'import json, sys
json.dump({"schema": 1, "boot": sys.argv[2]}, open(sys.argv[1], "x"))' \
    "$OUT/completion-subject-$1.json" "$2"
}
# Each step's checker replays every native verdict and received frame up to its confirmation.
completion_wait() {
  local step=$1
  for _ in {1..100}; do
    if python3 "$completion_helper" step "$OUT" "$step" >/dev/null \
      2>>"$OUT/completion-$step-wait.log"; then
      return 0
    fi
    sleep 0.1
  done
  echo "FAIL: completion $step evidence not confirmed" >&2
  return 1
}
# The desktop change must advance the provider's context while the holder's popup stays active.
completion_popup_kept() {
  local baseline=$1
  for _ in {1..40}; do
    if python3 - "$OUT/kwin.log" "$OUT/focus-shell-pid.txt" "$baseline" \
      2>>"$OUT/completion-popup-wait.log" <<'PY'
import json, sys
lines = open(sys.argv[1]).readlines()[int(sys.argv[3]):]
rows = [json.loads(line.split("layout-probe-focus ", 1)[1]) for line in lines
        if line.endswith("\n") and "layout-probe-focus " in line]
changed = [row for row in rows if row["event"] == "context-changed"]
assert changed, "no context change since the desktop was created"
shell = int(open(sys.argv[2]).read())
assert all(row["activeAppletPopup"] and row["activePid"] == shell for row in changed), changed
PY
    then
      return 0
    fi
    sleep 0.1
  done
  echo "FAIL: the desktop change did not leave the holder's popup active" >&2
  return 1
}

# The competitor's first observation and control geometry may arrive independently.
completion_competitor() {
  for _ in {1..40}; do
    if python3 - "$OUT/plasmashell.log" "$OUT/kwin.log" "$focus_boot" \
      2>>"$OUT/completion-competitor-wait.log" <<'PY'
import json, sys
latest, controls = {}, {}
for line in open(sys.argv[1]):
    for marker, rows in (("layout-probe-observation ", latest),
                         ("layout-probe-focus-control ", controls)):
        if line.endswith("\n") and marker in line:
            row = json.loads(line.split(marker, 1)[1])
            rows[row["boot"]] = row
boots = set(latest) - {sys.argv[3]}
assert len(boots) == 1, boots
boot = boots.pop()
focus = [json.loads(line.split("layout-probe-focus ", 1)[1]) for line in open(sys.argv[2])
         if line.endswith("\n") and "layout-probe-focus " in line]
alpha = [row for row in focus if row["rememberedClass"] == "pf.focus.alpha"
         and row["rememberedCenter"]][-1]["rememberedCenter"]
assert 0 < alpha["x"] < 1440 and 0 < alpha["y"] < 900, alpha
print(boot, controls[boot]["x"], controls[boot]["y"], alpha["x"], alpha["y"])
PY
    then
      return 0
    fi
    sleep 0.1
  done
  echo "FAIL: the competitor's observation and focus control were not ready" >&2
  return 1
}

# 1. The holder's preparation was accepted just before this case began.
completion_subject holder "$focus_boot"
completion_wait accepted

# 2. A context change: closing the popup moves focus, and the provider publishes again.
completion_mark context
pfinput "key esc"
completion_wait context

# 3. Another consumer's request: the competitor prepares from a menu opened from the app.
completion_competitor >"$OUT/completion-competitor.txt"
read -r competitor_boot competitor_x competitor_y alpha_x alpha_y \
  <"$OUT/completion-competitor.txt"
completion_subject competitor "$competitor_boot"
pfinput "click $alpha_x $alpha_y"
wait_target_context "$competitor_boot" pf.focus.alpha
pfinput "click $competitor_x $competitor_y"
wait_target_popup pf.focus.alpha
completion_mark competitor
pfinput "key space"
completion_wait competitor

# 4. The refusal is kept: closing the competitor's popup publishes again.
completion_mark refusal
pfinput "key esc"
completion_wait refusal

# 5. A refusal the previous probe re-decided: the holder prepares from a menu whose captured
#    context a desktop change made stale while the popup stayed open.
pfinput "click $alpha_x $alpha_y"
wait_target_context "$focus_boot" pf.focus.alpha
pfinput "click $focus_x $focus_y"
wait_target_popup pf.focus.alpha
completion_baseline=$(wc -l <"$OUT/kwin.log")
qdbus org.kde.KWin /VirtualDesktopManager org.kde.KWin.VirtualDesktopManager.createDesktop \
  2 "Completion probe" >/dev/null
completion_popup_kept "$completion_baseline"
completion_mark stale
pfinput "key space"
completion_wait stale

# 6. That refusal is kept: closing the popup publishes again.
completion_mark stale-kept
pfinput "key esc"
completion_wait stale-kept

# The checker recomputes every step record from the raw logs before it writes the receipt.
python3 "$completion_helper" receipt "$OUT"
echo "PASS: decided completions survive newer frames; validity is reported separately"
