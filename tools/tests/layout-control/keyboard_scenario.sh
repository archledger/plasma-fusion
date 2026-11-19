#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# Sourced by scenario-bridge.sh in keyboard-entry seeds only, once the controlled app is active and
# the focus consumer holds a context that remembers it, before any pointer opens the popup. The
# caller keeps the cleanup helper's ownership of the shell; this scenario quits the caller's app.
# The probe panel gets keyboard focus from plasmashell's 'Move keyboard focus between panels'
# shortcut (Meta+Alt+P), a key on its focused control opens the probe popup, and a key in the popup
# prepares: first with the app remembered, then after the app has closed, from the desktop.
set -euo pipefail

# These are native session actions, so also require a real private container.
[[ ${PFV:-} == /var/tmp/pfv-layout-control-* && ${HOME:-} == "$PFV/home" &&
   ${XDG_RUNTIME_DIR:-} == "$PFV/run" && ${PF_LAYOUT_PRIVATE_CONTAINER:-} == 1 &&
   -f /run/.containerenv ]] || {
  echo "Refusing a non-private keyboard-entry scenario" >&2
  return 64
}
: "${OUT:?private output}" "${focus_boot:?target prelude}" "${focus_input:?target prelude}" \
  "${focus_client:?target prelude}"

keyboard_helper="$HOME/.local/lib/layout-control/keyboard_entry.py"
receipts="$HOME/.local/lib/layout-control/receipts.py"
keyboard_mark() { python3 "$keyboard_helper" mark "$OUT" "$1" >/dev/null; }
# The provider's newest focus row shows the shell's SURFACE (dock or popup) active, remembering
# APP or, for "-", nothing.
keyboard_wait() {
  local surface=$1 app=$2
  for _ in {1..40}; do
    if python3 - "$OUT/kwin.log" "$OUT/focus-shell-pid.txt" "$surface" "$app" \
      2>>"$OUT/keyboard-$surface-wait.log" <<'PY'
import json, sys
rows = [json.loads(line.split("layout-probe-focus ", 1)[1])
        for line in open(sys.argv[1]) if line.endswith("\n") and "layout-probe-focus " in line]
row = rows[-1]
assert row["activePid"] == int(open(sys.argv[2]).read()) and row["activeNormal"] is False
if sys.argv[3] == "dock":
    assert row["activeDock"] is True and row["activeAppletPopup"] is False
else:
    assert row["activeAppletPopup"] is True
if sys.argv[4] == "-":
    assert row["rememberedClass"] == "" and row["rememberedAlive"] is False
else:
    assert row["rememberedClass"] == sys.argv[4] and row["rememberedAlive"] is True
PY
    then
      return 0
    fi
    sleep 0.1
  done
  echo "FAIL: keyboard entry: no $surface with ${app/#-/nothing} remembered" >&2
  return 1
}
# Once the app has closed, the provider remembers nothing.
keyboard_forgotten() {
  for _ in {1..40}; do
    if python3 - "$OUT/kwin.log" 2>>"$OUT/keyboard-forgotten-wait.log" <<'PY'
import json, sys
rows = [json.loads(line.split("layout-probe-focus ", 1)[1])
        for line in open(sys.argv[1]) if line.endswith("\n") and "layout-probe-focus " in line]
assert rows[-1]["rememberedClass"] == "" and rows[-1]["rememberedAlive"] is False
PY
    then
      return 0
    fi
    sleep 0.1
  done
  echo "FAIL: keyboard entry: the closed app is still remembered" >&2
  return 1
}
# The focus consumer's current request number.
keyboard_request() {
  python3 - "$OUT/plasmashell.log" "$focus_boot" <<'PY'
import json, sys
rows = [json.loads(line.split("layout-probe-observation ", 1)[1])
        for line in open(sys.argv[1])
        if line.endswith("\n") and "layout-probe-observation " in line]
print([row for row in rows if row["boot"] == sys.argv[2]][-1]["request"])
PY
}

# Only the probe panel stays, so the shortcut's first panel is the probe panel.
evaljs - >"$OUT/keyboard-panels-removed.txt" <<'JS'
var removed = [];
panels().forEach(function(p) {
    if (p.widgets("org.plasmafusion.layoutprobe").length === 0) {
        removed.push(p.id);
        p.remove();
    }
});
print(JSON.stringify(removed));
JS
evaljs - >"$OUT/keyboard-panels.txt" <<'JS'
print(JSON.stringify(panels().map(function(p) {
    return p.widgets("org.plasmafusion.layoutprobe").length;
})));
JS
[[ $(cat "$OUT/keyboard-panels.txt") == "[2]" ]] || {
  echo "FAIL: keyboard entry: other panels remain" >&2
  return 1
}
wait_target_context "$focus_boot" pf.focus.alpha

# The panel's activation keeps the remembered app; the popup it opens bridges one generation, so
# the key on the panel waits until the consumer holds the context after the panel's activation.
keyboard_mark entry
generation=$(python3 "$receipts" provider-generation "$OUT/kwin.log")
previous=$(keyboard_request)
pfinput "key meta+alt+p"
keyboard_wait dock pf.focus.alpha
wait_target_settled "$focus_boot" $((generation + 1))
pfinput "key space"
keyboard_wait popup pf.focus.alpha
pfinput "key space"
target_request=$(wait_target_reply "$focus_boot" prepare true "$previous" pf.focus.alpha)
echo "PASS: keyboard entry after panel focus prepares the remembered app, never the panel"
pfinput "key esc"

# With the app closed nothing eligible is remembered, so the same keys must be refused.
printf 'quit\n' >&"$focus_input"
wait "$focus_client"
exec {focus_input}>&-
keyboard_forgotten
keyboard_mark refusal
generation=$(python3 "$receipts" provider-generation "$OUT/kwin.log")
pfinput "key meta+alt+p"
keyboard_wait dock -
wait_target_settled "$focus_boot" $((generation + 1))
pfinput "key space"
keyboard_wait popup -
pfinput "key space"
target_request=$(wait_target_reply "$focus_boot" prepare false "$target_request" -)
echo "PASS: keyboard entry without an eligible app refuses safely, never the panel"
pfinput "key esc"

# The checker recomputes both steps from the raw logs before it writes the receipt.
python3 "$keyboard_helper" receipt "$OUT"
echo "PASS: keyboard entry after panel focus: the remembered app or a safe refusal, never the panel"
