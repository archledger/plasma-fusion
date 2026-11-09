# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Exercise the real session launch fragment with deterministic interleaved writers."""
import json
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[3]


class SessionLogTests(unittest.TestCase):
    def test_bus_prefix_cannot_corrupt_compositor_records(self):
        source = (ROOT / "tools/vsession/vsession.sh").read_text()
        start = source.index('env -i "${EXTRA_ENV[@]}"')
        end = source.index('kill "$WATCHDOG"', start)
        fragment = source[start:end]
        for status in (0, 37):
            with self.subTest(status=status), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                (root / "out").mkdir()
                bus = root / "bus"
                bus.write_text('#!/bin/bash\nshift\nexec 9>"$PFV/writer.lock"\nflock 9\n'
                               'printf "BUS prefix: " >&2\n"$@"\nrc=$?\n'
                               '( for ((i=0; i<500; i++)); do\n'
                               '  [[ -e "$PFV/release" ]] && break\n  sleep 0.01\ndone\n'
                               'printf "Aborted late service\\n" >&2 ) &\nexit "$rc"\n')
                compositor = root / "compositor"
                compositor.write_text(
                    '#!/usr/bin/python3\nimport json,os,pathlib,sys\n'
                    'pathlib.Path(os.environ["PFV"], "arguments.json").write_text(json.dumps(sys.argv[1:]))\n'
                    'print("PFTHUMB CLIENTS 1", flush=True)\n'
                    'print("native diagnostic", file=sys.stderr, flush=True)\n'
                    f'sys.exit({status})\n')
                bus.chmod(0o755)
                compositor.chmod(0o755)
                launch = fragment.replace("dbus-run-session", str(bus)).replace("kwin_wayland", str(compositor))
                setup = (f'PFV={shlex.quote(directory)}\nEXTRA_ENV=(); OPT_ENV=(); '
                         'KWIN_OPTS=(--no-lockscreen); CONFIG_DIRS=/etc/xdg\n'
                         'TMO=5; W=1280; H=800; NAME="session with spaces"\n')
                result = subprocess.run(["bash"], input=setup + launch + 'exit "$rc"\n',
                                        text=True, capture_output=True, timeout=10)
                self.assertEqual(result.returncode, status, result.stderr)
                (root / "release").touch()
                subprocess.run(["flock", "-x", "-w", "10", str(root / "writer.lock"), "true"],
                               check=True, timeout=15)
                native = (root / "out/kwin.log").read_text()
                self.assertIn("PFTHUMB CLIENTS 1", native.splitlines())
                self.assertIn("native diagnostic", native.splitlines())
                self.assertNotIn("BUS prefix:", native)
                self.assertEqual((root / "out/dbus.log").read_text(), "BUS prefix: Aborted late service\n")
                args = json.loads((root / "arguments.json").read_text())
                self.assertEqual(args[args.index("--socket") + 1], "pfv-session with spaces")
                self.assertEqual(args[-1], str(root / "inner.sh"))


if __name__ == "__main__":
    unittest.main()
