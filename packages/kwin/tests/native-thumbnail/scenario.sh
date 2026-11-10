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
mode=normal
if [[ -f "$HOME/thumbnail-case" ]]; then
    read -r mode <"$HOME/thumbnail-case"
fi
case "$mode" in
    normal) ;;
    filtered)
        python3 "$HOME/pf-tools/tests/lib/pfkwin.py" run '
var w=workspace.stackingOrder.find(w=>w.caption==="Thumbnail target");
var other=workspace.stackingOrder.find(w=>w.caption==="Thumbnail other");
if (!w || !other) throw new Error("filter windows missing");
if (workspace.desktops.length < 2) workspace.createDesktop(1,"Thumbnail second");
workspace.currentDesktop=workspace.desktops[0];
w.desktops=[workspace.desktops[1]];
other.desktops=[workspace.desktops[0]];
report({otherWorkspace:w.desktops.length===1 && w.desktops[0]!==workspace.currentDesktop});' >"$OUT/filter-setup.json"
        python3 - "$OUT/filter-setup.json" <<'PY'
import json,sys
assert json.load(open(sys.argv[1]))['otherWorkspace'], 'target was not moved off the current workspace'
PY
        ;;
    *) echo 'unknown thumbnail case' >&2; exit 1 ;;
esac
# InputMethod adds two geometry listeners to the focused window. Keep them off the measured target.
python3 "$HOME/pf-tools/tests/lib/pfkwin.py" run '
var other=workspace.stackingOrder.find(w=>w.caption==="Thumbnail other");
if (!other) throw new Error("focus control window missing");
workspace.activeWindow=other;
if (workspace.activeWindow!==other) throw new Error("focus control not applied");
report({caption:other.caption,id:String(other.internalId)});' >"$OUT/focus-setup.json"
sleep 0.2
commands=()
for ((i=0; i<12; i++)); do
    commands+=('keydown alt' 'key tab' 'sleep 0.25')
    if [[ "$mode" == filtered ]]; then
        commands+=('key a' 'sleep 0.25' 'key a' 'sleep 0.25')
    fi
    commands+=('key esc' 'keyup alt' 'sleep 0.25')
done
pfinput "${commands[@]}"
sleep 1
if [[ "$mode" == filtered ]]; then
    # A suspended off-workspace Qt client need not render a resized buffer. Expose it first.
    python3 "$HOME/pf-tools/tests/lib/pfkwin.py" run '
var w=workspace.stackingOrder.find(w=>w.caption==="Thumbnail target");
if (!w) throw new Error("target missing before resize");
w.desktops=[workspace.currentDesktop];
if (w.desktops.length!==1 || w.desktops[0]!==workspace.currentDesktop) {
    throw new Error("target not on current workspace before resize");
}
report({id:String(w.internalId),currentWorkspace:true});' >"$OUT/resize-setup.json"
    sleep 0.3
fi
python3 "$HOME/pf-tools/tests/lib/pfkwin.py" run '
var w=workspace.stackingOrder.find(w=>w.caption==="Thumbnail target");
if (!w) throw new Error("target missing");
w.frameGeometry={x:90,y:90,width:600,height:420}; report(w.caption);' >"$OUT/resize-request.json"
sleep 0.3
python3 "$HOME/pf-tools/tests/lib/pfkwin.py" run '
var w=workspace.stackingOrder.find(w=>w.caption==="Thumbnail target");
if (!w || w.frameGeometry.width !== 600 || w.frameGeometry.height !== 420) {
    throw new Error("target did not resize: " + JSON.stringify(w && w.frameGeometry));
}
report({id:String(w.internalId),width:w.frameGeometry.width,height:w.frameGeometry.height});' >"$OUT/resized.json"
shot resized
verify_native after
# shellcheck source=finish-session.sh
source "$HOME/finish-session.sh"
)
