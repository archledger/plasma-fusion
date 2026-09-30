#!/bin/bash
# KWin packages: window switcher org.plasmafusion.switcher and the KWin scripts
# plasmafusion-snap (Meta+Z snap layouts, fill the other half, snap-zone outline) and
# plasmafusion-attach (modal dialogs attached to their window). Installed like
# kpackagetool6 -t KWin/WindowSwitcher|KWin/Script -i would, at
#   $STAGE/.local/share/kwin/tabbox/org.plasmafusion.switcher/
#   $STAGE/.local/share/kwin/scripts/plasmafusion-snap/     (outline: contents/outline/outline.qml)
#   $STAGE/.local/share/kwin/scripts/plasmafusion-attach/
# The switcher and the snap script get a copy of packages/common/FusionMetrics.qml in contents/ui.
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
  [ -z "$(find "$1" -name FusionMetrics.qml)" ] || { echo "kwin: $1 has its own FusionMetrics.qml" >&2; exit 1; }
  rm -rf "$2"
  mkdir -p "$2"
  cp -r "$1/metadata.json" "$1/contents" "$2/"
  if [ -d "$2/contents/ui" ]; then
    install -m 0644 "$ROOT/packages/common/FusionMetrics.qml" "$2/contents/ui/FusionMetrics.qml"
  fi
  find "$2" -type d -exec chmod 0755 {} +
  find "$2" -type f -exec chmod 0644 {} +
  echo "  $(basename "$2") -> ${2#"$STAGE"/}"
}

check_package "$SRC/switcher/org.plasmafusion.switcher" org.plasmafusion.switcher KWin/WindowSwitcher
check_package "$SRC/scripts/plasmafusion-snap" plasmafusion-snap KWin/Script
check_package "$SRC/scripts/plasmafusion-attach" plasmafusion-attach KWin/Script
test -f "$SRC/switcher/org.plasmafusion.switcher/contents/ui/main.qml"
test -f "$SRC/scripts/plasmafusion-snap/contents/ui/main.qml"
test -f "$SRC/scripts/plasmafusion-snap/contents/outline/outline.qml"
test -f "$SRC/scripts/plasmafusion-attach/contents/code/main.js"

install_package "$SRC/switcher/org.plasmafusion.switcher" "$STAGE/.local/share/kwin/tabbox/org.plasmafusion.switcher"
install_package "$SRC/scripts/plasmafusion-snap" "$STAGE/.local/share/kwin/scripts/plasmafusion-snap"
install_package "$SRC/scripts/plasmafusion-attach" "$STAGE/.local/share/kwin/scripts/plasmafusion-attach"
