#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# ThinkPad-only evidence recipe; never connects to the logged-in desktop bus.
set -euo pipefail
root=/home/test/Projects/plasma-fusion-kwin-issue115
package=/home/test/Projects/plasma-fusion-kwin-personal/package-20261102
fixtures=/home/test/Projects/plasma-fusion-kwin-personal/full-fusion-20261101/fixtures
label=${1:?unique attempt label required}
[[ "$label" =~ ^[a-z0-9-]+$ ]] || exit 64
out=$root/evidence/persistence-$label
mkdir "$out"
test -f "$fixtures/finish-session.sh"
cat >"$out/scenario.sh" <<'SCENARIO'
(
set -euo pipefail
probe=$PFV/config-probe
mkdir -p "$probe/writable" "$probe/readonly"
finish() {
    rc=$?
    trap - EXIT
    set +e
    chmod 700 "$probe/readonly"
    chmod 600 "$probe/readonly/state" 2>/dev/null
    # shellcheck source=/dev/null
    source /fixtures/finish-session.sh
    shutdown=$?
    printf '%s\n' "$rc" >"$OUT/probe.exit"
    printf '%s\n' "$shutdown" >"$OUT/shutdown.exit"
    exit "$rc"
}
trap finish EXIT
test "$(id -u)" != 0
rpm -q plasma-workspace qt6-qtbase >"$OUT/packages.txt"
rpm -qf /usr/lib64/libKF6ConfigCore.so.6 >>"$OUT/packages.txt"
for dir in writable readonly; do
    evaljs - >"$OUT/$dir-initial.reply" <<JS
var c = ConfigFile("$probe/$dir/state", "Windows");
print(c.writeEntry("windows", "P"));
JS
done
chmod 400 "$probe/readonly/state"
chmod 500 "$probe/readonly"
for dir in writable readonly; do
    evaljs - >"$OUT/$dir-write.reply" <<JS
var c = ConfigFile("$probe/$dir/state", "Windows");
print(c.writeEntry("windows", "A"));
JS
done
python3 - "$probe" "$OUT" <<'PY'
import configparser
import json
from pathlib import Path
import sys

probe, out = map(Path, sys.argv[1:])
result = {}
for name in ("writable", "readonly"):
    config = configparser.ConfigParser()
    config.read(probe / name / "state")
    result[name] = {
        "reply": (out / f"{name}-write.reply").read_text().strip(),
        "disk": config["Windows"]["windows"],
    }
(out / "persistence-result.json").write_text(json.dumps(result, indent=2) + "\n")
print(json.dumps(result, indent=2))
if result != {"writable": {"reply": "true", "disk": "A"},
              "readonly": {"reply": "true", "disk": "P"}}:
    raise SystemExit("Unexpected persistence semantics: retain evidence and investigate")
PY
)
SCENARIO
mkdir -p "$out/pfv-probe/home/.config"
cat >"$out/pfv-probe/home/.config/pfv-env" <<'ENV'
LD_LIBRARY_PATH=/kwin/lib64
QT_PLUGIN_PATH=/kwin/lib64/qt6/plugins:/usr/lib64/qt6/plugins
QML_IMPORT_PATH=/kwin/lib64/qt6/qml:/usr/lib64/qt6/qml
XDG_DATA_DIRS=/kwin/share:/usr/share
ENV
status=0
podman run --rm --pull=never --timeout=180 --stop-timeout=15 \
    --name=pf-nt01-persistence-20261102 --network=none --cap-drop=ALL \
    --security-opt=no-new-privileges --pids-limit=768 --cpus=2 --memory=4g \
    --userns=keep-id --user="$(id -u):$(id -g)" \
    --device=/dev/dri/renderD128:/dev/dri/renderD128:rw --group-add=keep-groups \
    --tmpfs /tmp:rw,nosuid,nodev,size=256m \
    -v "$package/candidate-root/usr:/kwin:ro,z" \
    -v "$fixtures:/fixtures:ro,z" -v "$out:/test:rw,Z" \
    --entrypoint=/bin/bash \
    8e21595bc487be7fec1bed0acaf240e20846b44c213cf0256e11cea8d8d78eae \
    -euc 'export PFV_BASE=/test; bash /fixtures/vsession.sh probe /test/scenario.sh 800x600 120;
          test "$(cat /test/pfv-probe/out/probe.exit)" = 0;
          test "$(cat /test/pfv-probe/out/shutdown.exit)" = 0' \
    >"$out/driver.log" 2>&1 || status=$?
printf '%s\n' "$status" >"$out/driver.exit"
cat "$out/driver.log"
exit "$status"
