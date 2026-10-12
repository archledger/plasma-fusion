#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Plasmoid org.plasmafusion.launcher (centred start menu). Copies the hand-written package into
# the staged HOME: $STAGE/.local/share/plasma/plasmoids/org.plasmafusion.launcher, with copies of
# the shared QML blocks it uses (packages/common/*.qml, tools/build-lib/shared-qml.sh) in contents/ui.
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

bash "$ROOT/tools/build-lib/shared-qml.sh" check "$src" launcher
# The tablet sheet's backdrop follows the widget's glass key (Glass = Solid, high contrast).
python3 -B "$ROOT/packages/common/tests/backdrop_glass_test.py" "$src"
# The settings page declares every key and default and refreshes the ones it does not edit.
python3 -B "$ROOT/packages/common/tests/config_page_keys_test.py" "$src"

if command -v node >/dev/null 2>&1; then
  node "$src/tests/date-timer.test.js" >/dev/null
fi

rm -rf "$dest"
mkdir -p "$dest"
cp -r "$src/metadata.json" "$src/contents" "$dest/"
bash "$ROOT/tools/build-lib/shared-qml.sh" install "$src" "$dest/contents/ui"
find "$dest" -type f -exec chmod 0644 {} +
echo "launcher: $dest"
