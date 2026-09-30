#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Lock-screen shell package org.plasmafusion.lockshell (Plasma/Shell holding only
# contents/lockscreen/; everything else falls back to org.kde.plasma.desktop)
# -> $STAGE/.local/share/plasma/shells/org.plasmafusion.lockshell/, with a copy of
# packages/common/FusionMetrics.qml in contents/lockscreen.
# It only takes effect once tools/device/lockscreen-enable.sh has pointed KWin's
# PLASMA_DEFAULT_SHELL at it (see docs/parts/lockscreen.md).
set -euo pipefail
: "${ROOT:?}" "${STAGE:?}"

ID=org.plasmafusion.lockshell
SRC=$ROOT/packages/lockscreen/$ID
DEST=$STAGE/.local/share/plasma/shells/$ID

# metadata: valid JSON, the right structure and id, API version 2 (kscreenlocker_greet refuses
# older shells) and the stock desktop shell as fallback.
python3 - "$SRC/metadata.json" "$ID" <<'EOF'
import json, sys
meta = json.load(open(sys.argv[1]))
assert meta["KPackageStructure"] == "Plasma/Shell", "KPackageStructure"
assert meta["KPlugin"]["Id"] == sys.argv[2], "KPlugin.Id"
assert int(meta["X-Plasma-APIVersion"]) >= 2, "X-Plasma-APIVersion"
assert meta["X-Plasma-FallbackPackage"] == "org.kde.plasma.desktop", "X-Plasma-FallbackPackage"
EOF

for f in LockScreen.qml LockScreenUi.qml MainBlock.qml NoPasswordUnlock.qml LockOsd.qml \
         MediaControls.qml PasswordSync.qml qmldir config.xml config.qml; do
  [ -s "$SRC/contents/lockscreen/$f" ] || { echo "lockscreen: missing contents/lockscreen/$f" >&2; exit 1; }
done
python3 -c 'import sys, xml.dom.minidom; xml.dom.minidom.parse(sys.argv[1])' "$SRC/contents/lockscreen/config.xml"

[ ! -e "$SRC/contents/lockscreen/FusionMetrics.qml" ] || { echo "lockscreen: the package has its own FusionMetrics.qml" >&2; exit 1; }

rm -rf "$DEST"
mkdir -p "$DEST/contents"
install -m 0644 "$SRC/metadata.json" "$DEST/metadata.json"
cp -r "$SRC/contents/lockscreen" "$DEST/contents/"
install -m 0644 "$ROOT/packages/common/FusionMetrics.qml" "$DEST/contents/lockscreen/FusionMetrics.qml"
find "$DEST" -type d -exec chmod 0755 {} +
find "$DEST" -type f -exec chmod 0644 {} +
echo "lockscreen: $(find "$DEST" -type f | wc -l) files in ${DEST#"$STAGE"/}"
