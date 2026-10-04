#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Lock-screen and log-out shell package org.plasmafusion.lockshell (Plasma/Shell holding
# contents/lockscreen/ and contents/logout/; everything else falls back to
# org.kde.plasma.desktop)
# -> $STAGE/.local/share/plasma/shells/org.plasmafusion.lockshell/, with copies of the shared QML
# blocks it uses (packages/common/*.qml, tools/build-lib/shared-qml.sh) in contents/lockscreen.
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

bash "$ROOT/tools/build-lib/shared-qml.sh" check "$SRC" lockscreen

rm -rf "$DEST"
mkdir -p "$DEST/contents"
install -m 0644 "$SRC/metadata.json" "$DEST/metadata.json"
cp -r "$SRC/contents/lockscreen" "$DEST/contents/"
bash "$ROOT/tools/build-lib/shared-qml.sh" install "$SRC" "$DEST/contents/lockscreen"
# The log-out screen: the same files the Global Theme carries (the Plasma 6.7 greeter reads them
# from there; the Plasma 6.8 greeter reads the shell package instead, plasma-workspace 3729037a).
for f in Logout.qml LogoutButton.qml timer.js; do
  [ -s "$ROOT/packages/look-and-feel/common/contents/logout/$f" ] ||
    { echo "lockscreen: missing look-and-feel contents/logout/$f" >&2; exit 1; }
done
cp -r "$ROOT/packages/look-and-feel/common/contents/logout" "$DEST/contents/"
find "$DEST" -type d -exec chmod 0755 {} +
find "$DEST" -type f -exec chmod 0644 {} +
echo "lockscreen: $(find "$DEST" -type f | wc -l) files in ${DEST#"$STAGE"/}"
