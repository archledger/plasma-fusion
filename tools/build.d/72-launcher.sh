#!/bin/bash
# Plasmoid org.plasmafusion.launcher (centred start menu). Copies the hand-written package into
# the staged HOME: $STAGE/.local/share/plasma/plasmoids/org.plasmafusion.launcher, with a copy of
# packages/common/FusionMetrics.qml in contents/ui.
set -euo pipefail
: "${ROOT:?}" "${STAGE:?}"

id=org.plasmafusion.launcher
src="$ROOT/packages/plasmoids/$id"
dest="$STAGE/.local/share/plasma/plasmoids/$id"

python3 - "$src/metadata.json" <<'PY'
import json, sys
meta = json.load(open(sys.argv[1]))
assert meta["KPlugin"]["Id"] == "org.plasmafusion.launcher", "wrong plugin id"
assert "org.kde.plasma.launchermenu" in meta.get("X-Plasma-Provides", []), "missing launchermenu provider"
PY

[ ! -e "$src/contents/ui/FusionMetrics.qml" ] || { echo "launcher: the package has its own FusionMetrics.qml" >&2; exit 1; }

rm -rf "$dest"
mkdir -p "$dest"
cp -r "$src/metadata.json" "$src/contents" "$dest/"
install -m 0644 "$ROOT/packages/common/FusionMetrics.qml" "$dest/contents/ui/FusionMetrics.qml"
find "$dest" -type f -exec chmod 0644 {} +
echo "launcher: $dest"
