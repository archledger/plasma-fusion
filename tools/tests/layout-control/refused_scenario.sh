#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# Sourced by scenario-bridge.sh in refused-backend seeds only, before the probe is loaded; the
# caller retains child/cleanup ownership. Only the occupier starts with the session, so it holds
# the fork's native provider slot and the probe's own registration is refused. This case loads
# and unloads the two private test scripts; it changes nothing else.
set -euo pipefail

# Script loading is a native session action, so also require a real private container.
[[ ${PFV:-} == /var/tmp/pfv-layout-control-* && ${HOME:-} == "$PFV/home" &&
   ${XDG_RUNTIME_DIR:-} == "$PFV/run" && ${PF_LAYOUT_PRIVATE_CONTAINER:-} == 1 &&
   -f /run/.containerenv ]] || {
  echo "Refusing a non-private refused-backend scenario" >&2
  return 64
}

refused_helper="$HOME/.local/lib/layout-control/refused_backend.py"
refused_probe="$HOME/.local/share/kwin/scripts/plasmafusion-layout-probe/contents/ui/main.qml"
refused_mark() { python3 "$refused_helper" mark "$OUT" "$1" >/dev/null; }
# A step's checker reads only the complete log lines since its mark.
refused_wait() {
  local step=$1
  for _ in {1..100}; do
    if python3 "$refused_helper" step "$OUT" "$step" >/dev/null \
      2>>"$OUT/refused-$step-wait.log"; then
      return 0
    fi
    sleep 0.1
  done
  echo "FAIL: refused-backend $step evidence not confirmed" >&2
  return 1
}
refused_loaded() {
  [[ $(qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.isScriptLoaded "$1") == "$2" ]]
}
# Scripting.start, which KWin also runs whenever its configuration changes, would re-read
# [Plugins] and unload this probe again, because the seed disables it there (KWin's
# Scripting::queryScriptsToLoad), so run only the script just loaded, by its own
# /Scripting/Script<id> object. KWin numbers a script by the current script count, so first wait
# until an unloaded probe is really gone; until then its number and object may still be in use.
# The occupier is the only other script in this session, so the expected number is known. Any
# other number means the session holds other scripts than assumed; the number may then also
# belong to one of them, whose object run would reach instead.
refused_load_probe() {
  local expected=$1 id
  for _ in {1..100}; do
    refused_loaded plasmafusion-layout-probe false && break
    sleep 0.1
  done
  refused_loaded plasmafusion-layout-probe false || {
    echo "FAIL: the previous probe is still loaded" >&2
    return 1
  }
  id=$(qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.loadDeclarativeScript \
    "$refused_probe" plasmafusion-layout-probe)
  [[ $id == "$expected" ]] || {
    echo "FAIL: the probe got script number $id, not $expected" >&2
    return 1
  }
  printf '%s\n' "$id" >>"$OUT/refused-script-ids.txt"
  qdbus org.kde.KWin "/Scripting/Script$id" org.kde.kwin.Script.run
}
refused_unload() {
  [[ $(qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript "$1") == true ]] || {
    echo "FAIL: $1 did not unload" >&2
    return 1
  }
}
refused_wake() {
  qdbus org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component.invokeShortcut \
    "Plasma Fusion: Layout Probe Wake"
}

refused_loaded plasmafusion-layout-occupier true || {
  echo "FAIL: the occupier did not start with the session" >&2
  return 1
}
refused_loaded plasmafusion-layout-probe false || {
  echo "FAIL: the probe started before the occupier case" >&2
  return 1
}
refused_mark start
refused_wait occupied

# Lifetime 1: refused while the occupier holds the slot; both widgets must report unsupported.
refused_mark load-1
refused_load_probe 1
evaljs - >"$OUT/widgets-created.txt" <<'JS'
var p=new Panel;
p.location="top";
p.height=40;
var a=p.addWidget("org.plasmafusion.layoutprobe");
var b=p.addWidget("org.plasmafusion.layoutprobe");
print(JSON.stringify([a.id,b.id]));
JS
refused_wait refused-1

# Lifetime 2: still refused after a reload; it must not reuse lifetime 1's label or alias.
refused_mark reload-1
refused_unload plasmafusion-layout-probe
refused_load_probe 1
refused_wake
refused_wait refused-2

# Destroying the occupier object releases the native slot.
refused_mark release
refused_unload plasmafusion-layout-occupier
refused_wait released

# Lifetime 3: the reloaded probe is accepted with a third label. With the occupier gone it is
# the only script, so KWin numbers it 0.
refused_mark reload-2
refused_unload plasmafusion-layout-probe
refused_load_probe 0
refused_wake
refused_wait accepted

# The checker recomputes every step and audits the run before it writes the receipt.
python3 "$refused_helper" receipt "$OUT"
echo "PASS: refused native registration, distinct refused lifetimes and accepted recovery"
