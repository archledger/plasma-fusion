# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck shell=bash
(
set -euo pipefail
[[ "$XDG_RUNTIME_DIR" == "$PFV/run" ]] || { echo 'not a private test runtime' >&2; exit 1; }
pid=$(qdbus org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus.GetConnectionUnixProcessID org.kde.plasmashell)
python3 - "$pid" "$XDG_RUNTIME_DIR" <<'PY'
from pathlib import Path
import sys
pid, runtime = sys.argv[1:]
assert ('XDG_RUNTIME_DIR=' + runtime).encode() in Path(f'/proc/{pid}/environ').read_bytes().split(b'\0')
PY
timeout 5 kquitapp6 plasmashell
python3 - "$pid" "$OUT/shutdown.json" <<'PY'
from pathlib import Path
import json
import subprocess
import sys
import time

pid, receipt = sys.argv[1:]
deadline = time.monotonic() + 5
while time.monotonic() < deadline:
    result = subprocess.run(['qdbus-qt6', 'org.freedesktop.DBus', '/org/freedesktop/DBus',
                             'org.freedesktop.DBus.NameHasOwner', 'org.kde.plasmashell'],
                            text=True, capture_output=True, check=True, timeout=1)
    stat = Path(f'/proc/{pid}/stat')
    try:
        exited = stat.read_text().split(') ', 1)[1].startswith('Z ')
    except FileNotFoundError:
        exited = True
    if result.stdout.strip() == 'false' and exited:
        Path(receipt).write_text(json.dumps({'private_plasmashell_pid': int(pid), 'exited': True}) + '\n')
        break
    time.sleep(0.05)
else:
    raise AssertionError('private plasmashell did not finish its graceful shutdown')
PY
echo 'PASS: private plasmashell exited before bus teardown'
)
