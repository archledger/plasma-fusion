#!/bin/bash
# Plasmoid org.plasmafusion.launcher (centred start menu). Copies the hand-written package into
# the staged HOME: $STAGE/.local/share/plasma/plasmoids/org.plasmafusion.launcher
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

rm -rf "$dest"
mkdir -p "$dest"
cp -r "$src/metadata.json" "$src/contents" "$dest/"
find "$dest" -type f -exec chmod 0644 {} +
echo "launcher: $dest"
