# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck shell=bash
(
set -euo pipefail
verify_native() {
    local phase=$1 pid
    pid=$(qdbus org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus.GetConnectionUnixProcessID org.kde.KWin)
    python3 - "$pid" "$HOME" "$OUT" "$phase" <<'PY'
from pathlib import Path
import hashlib
import json
import sys

pid, home, output, phase = sys.argv[1:]
expected = json.loads(Path(home, 'expected-native.json').read_text())
maps = Path(f'/proc/{pid}/maps').read_text()
actual = {}
for name, digest in expected['files'].items():
    path = Path(f'/proc/{pid}/exe') if name == 'kwin_wayland' else Path('/usr/lib64', name)
    assert name == 'kwin_wayland' or str(path) in maps, f'{name} is not mapped'
    actual[name] = hashlib.sha256(path.read_bytes()).hexdigest()
    assert actual[name] == digest, f'wrong runtime binary: {name}'
if phase == 'after':
    path = Path(home, 'probe-qml/org/plasmafusion/thumbnailprobe/libthumbnailprobe.so')
    assert str(path) in maps, 'native probe is not mapped'
    actual['probe'] = hashlib.sha256(path.read_bytes()).hexdigest()
    assert actual['probe'] == expected['probe'], 'wrong native probe'
Path(output, f'native-{phase}.json').write_text(json.dumps(actual, indent=2) + '\n')
print(f'PASS: native binary provenance {phase}')
PY
}
verify_native before
cat > "$HOME/target.qml" <<'QML'
import QtQuick
Window { visible: true; width: 500; height: 350; title: "Thumbnail target"; color: "#294871" }
QML
cat > "$HOME/other.qml" <<'QML'
import QtQuick
Window { visible: true; width: 400; height: 300; title: "Thumbnail other"; color: "#613d42" }
QML
qml "$HOME/target.qml" >"$OUT/target.log" 2>&1 &
qml "$HOME/other.qml" >"$OUT/other.log" 2>&1 &
sleep 2
commands=()
for ((i=0; i<12; i++)); do
    commands+=('keydown alt' 'key tab' 'sleep 0.25' 'key esc' 'keyup alt' 'sleep 0.25')
done
pfinput "${commands[@]}"
sleep 1
python3 "$HOME/pf-tools/tests/lib/pfkwin.py" run '
var w=workspace.stackingOrder.find(w=>w.caption==="Thumbnail target");
if (!w) throw new Error("target missing");
w.frameGeometry={x:90,y:90,width:600,height:420}; report(w.caption);' >"$OUT/resize-request.json"
sleep 0.3
python3 "$HOME/pf-tools/tests/lib/pfkwin.py" run '
var w=workspace.stackingOrder.find(w=>w.caption==="Thumbnail target");
if (!w || w.frameGeometry.width !== 600 || w.frameGeometry.height !== 420) {
    throw new Error("target did not resize");
}
report({id:String(w.internalId),width:w.frameGeometry.width,height:w.frameGeometry.height});' >"$OUT/resized.json"
shot resized
verify_native after
# shellcheck source=finish-session.sh
source "$HOME/finish-session.sh"
)
