#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# KWin packages: window switcher org.plasmafusion.switcher and the KWin scripts
# plasmafusion-snap (Meta+Z snap layouts, fill the other half, snap-zone outline),
# plasmafusion-attach (modal dialogs attached to their window), plasmafusion-placement
# (window position and size remembered per app) and plasmafusion-workspaces (dynamic workspaces,
# off until turned on). Installed like
# kpackagetool6 -t KWin/WindowSwitcher|KWin/Script -i would, at
#   $STAGE/.local/share/kwin/tabbox/org.plasmafusion.switcher/
#   $STAGE/.local/share/kwin/scripts/plasmafusion-snap/     (outline: contents/outline/outline.qml)
#   $STAGE/.local/share/kwin/scripts/plasmafusion-attach/
#   $STAGE/.local/share/kwin/scripts/plasmafusion-placement/
#   $STAGE/.local/share/kwin/scripts/plasmafusion-workspaces/
# The switcher and the snap script get copies of the shared QML blocks they use (packages/common/*.qml,
# tools/build-lib/shared-qml.sh) in contents/ui. The placement script's pure rules (contents/ui/
# Placement.js) are tested by packages/kwin/tests/placement.test.js, the snap script's snap groups
# (contents/ui/Groups.js) by packages/kwin/tests/snap-groups.test.js, its touchpad gestures
# (contents/ui/Gestures.js) by packages/kwin/tests/gestures.test.js and the dynamic workspaces'
# rules (contents/ui/Workspaces.js) by packages/kwin/tests/workspaces.test.js, when node is
# installed.
set -euo pipefail
: "${ROOT:?}" "${STAGE:?}"

SRC=$ROOT/packages/kwin

check_package() { # $1 source dir, $2 expected id, $3 expected KPackageStructure
  python3 - "$1" "$2" "$3" <<'PY'
import json, sys, pathlib, xml.dom.minidom
src, pid, structure = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
meta = json.loads((src / "metadata.json").read_text())
assert meta["KPlugin"]["Id"] == pid, f"{src}: KPlugin.Id is not {pid}"
assert meta["KPackageStructure"] == structure, f"{src}: KPackageStructure is not {structure}"
for f in list(src.rglob("*.xml")) + list(src.rglob("*.ui")):
    xml.dom.minidom.parse(str(f))
PY
}

install_package() { # $1 source dir, $2 destination dir
  bash "$ROOT/tools/build-lib/shared-qml.sh" check "$1" "kwin: $1"
  rm -rf "$2"
  mkdir -p "$2"
  cp -r "$1/metadata.json" "$1/contents" "$2/"
  if [ -d "$2/contents/ui" ]; then
    bash "$ROOT/tools/build-lib/shared-qml.sh" install "$1" "$2/contents/ui"
  fi
  find "$2" -type d -exec chmod 0755 {} +
  find "$2" -type f -exec chmod 0644 {} +
  echo "  $(basename "$2") -> ${2#"$STAGE"/}"
}

check_package "$SRC/switcher/org.plasmafusion.switcher" org.plasmafusion.switcher KWin/WindowSwitcher
check_package "$SRC/scripts/plasmafusion-snap" plasmafusion-snap KWin/Script
check_package "$SRC/scripts/plasmafusion-attach" plasmafusion-attach KWin/Script
check_package "$SRC/scripts/plasmafusion-placement" plasmafusion-placement KWin/Script
check_package "$SRC/scripts/plasmafusion-workspaces" plasmafusion-workspaces KWin/Script
test -f "$SRC/switcher/org.plasmafusion.switcher/contents/ui/main.qml"
test -f "$SRC/scripts/plasmafusion-snap/contents/ui/main.qml"
test -f "$SRC/scripts/plasmafusion-snap/contents/outline/outline.qml"
test -f "$SRC/scripts/plasmafusion-attach/contents/code/main.js"
test -f "$SRC/scripts/plasmafusion-placement/contents/ui/main.qml"
test -f "$SRC/scripts/plasmafusion-workspaces/contents/ui/main.qml"

# The placement rules, snap groups, directional keys, legacy snap cycle, ensure-topbars.js's answer,
# dynamic workspaces and touchpad gestures (Placement.js, Groups.js, Directional.js, Cycle.js, Panels.js,
# Workspaces.js, Gestures.js) against their node suites, when node is installed.
if command -v node >/dev/null 2>&1; then
  node "$ROOT/packages/kwin/tests/placement.test.js" >/dev/null
  node "$ROOT/packages/kwin/tests/snap-groups.test.js" >/dev/null
  node "$ROOT/packages/kwin/tests/snap-cycle.test.js" >/dev/null
  node "$ROOT/packages/kwin/tests/snap-directional.test.js" >/dev/null
  node "$ROOT/packages/kwin/tests/panels.test.js" >/dev/null
  node "$ROOT/packages/kwin/tests/workspaces.test.js" >/dev/null
  node "$ROOT/packages/kwin/tests/gestures.test.js" >/dev/null
fi

install_package "$SRC/switcher/org.plasmafusion.switcher" "$STAGE/.local/share/kwin/tabbox/org.plasmafusion.switcher"
install_package "$SRC/scripts/plasmafusion-snap" "$STAGE/.local/share/kwin/scripts/plasmafusion-snap"
install_package "$SRC/scripts/plasmafusion-attach" "$STAGE/.local/share/kwin/scripts/plasmafusion-attach"
install_package "$SRC/scripts/plasmafusion-placement" "$STAGE/.local/share/kwin/scripts/plasmafusion-placement"
install_package "$SRC/scripts/plasmafusion-workspaces" "$STAGE/.local/share/kwin/scripts/plasmafusion-workspaces"

# The hot-plug check (KWIN-2): the snap script sends the Global Theme's ensure-topbars.js to
# plasmashell when screens change. A KWin script cannot read files, so the script's text goes into
# a JavaScript library next to main.qml (one source: packages/look-and-feel).
TOPBARS=$ROOT/packages/look-and-feel/common/contents/layouts/ensure-topbars.js
test -s "$TOPBARS"
python3 - "$TOPBARS" "$STAGE/.local/share/kwin/scripts/plasmafusion-snap/contents/ui/ensureTopBars.js" <<'PY'
import json, pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text()
assert "\u2028" not in text and "\u2029" not in text
pathlib.Path(sys.argv[2]).write_text(
    "// Generated by tools/build.d/80-kwin.sh from packages/look-and-feel/common/contents/layouts/ensure-topbars.js\n"
    ".pragma library\n"
    "var script = " + json.dumps(text) + ";\n")
PY
chmod 0644 "$STAGE/.local/share/kwin/scripts/plasmafusion-snap/contents/ui/ensureTopBars.js"
echo "  plasmafusion-snap: ensureTopBars.js from the Global Theme's ensure-topbars.js"

# The switcher's preview shader (KWIN-2): compiled from its source when Qt's qsb is installed, so
# the staged file always matches the source; without qsb the compiled file kept in the repository
# is used as it is.
SHADERS=$STAGE/.local/share/kwin/tabbox/org.plasmafusion.switcher/contents/ui/shaders
test -s "$SRC/switcher/org.plasmafusion.switcher/contents/ui/shaders/thumbnail.frag.qsb"
QSB=$(command -v qsb || true)
for candidate in /usr/lib64/qt6/bin/qsb /usr/lib/qt6/bin/qsb; do
  [ -n "$QSB" ] || { [ -x "$candidate" ] && QSB=$candidate; } || true
done
if [ -n "$QSB" ]; then
  "$QSB" --qt6 -o "$SHADERS/thumbnail.frag.qsb" "$SHADERS/thumbnail.frag"
  echo "  switcher shader: compiled with $QSB"
else
  echo "  switcher shader: qsb not installed, using the compiled file from the repository"
fi
