#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Check image and render-device selection through the real driver, stopping before any container
is built or any session starts."""

import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class ImageSelectionTest(unittest.TestCase):
    def drive(self, version, *options, images=False):
        """run.sh on a made-up KWin VERSION build, with stand-ins for podman (IMAGES: whether every
        image exists) and for env, through which run.sh starts each session (cvsession.sh). Returns
        the result and the arguments of each podman call and of each session's env call."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            rpms = root / "rpms"
            rpms.mkdir()
            rpm_name = f"kwin-{version}-3.fc44.pf1.x86_64.rpm"
            (rpms / rpm_name).write_bytes(b"image-selection fixture")
            digest = hashlib.sha256((rpms / rpm_name).read_bytes()).hexdigest()
            (rpms / "SHA256SUMS").write_text(f"{digest}  {rpm_name}\n")
            stage = root / "stage"
            (stage / ".local/share/plasma").mkdir(parents=True)
            tools = root / "bin"
            tools.mkdir()
            podman = tools / "podman"
            podman.write_text(
                '#!/usr/bin/env python3\nimport json,os,sys\n'
                'with open(os.environ["PODMAN_CALLS"], "a") as stream:\n'
                '    stream.write(json.dumps(sys.argv[1:]) + "\\n")\n'
                'command = sys.argv[1]\n'
                'if command in ("ps", "rmi"): sys.exit(0)\n'
                'if command == "image": sys.exit(0 if os.environ.get("PODMAN_IMAGES") else 1)\n'
                'if command == "build": sys.exit(1)\n'
                'sys.exit(91)\n')
            podman.chmod(0o755)
            # The session's variables and the cvsession.sh command line; the session fails at once.
            session = tools / "env"
            session.write_text(
                '#!/usr/bin/env python3\nimport json,os,sys\n'
                'with open(os.environ["SESSION_CALLS"], "a") as stream:\n'
                '    stream.write(json.dumps(sys.argv[1:]) + "\\n")\n'
                'sys.exit(1)\n')
            session.chmod(0o755)
            calls = root / "podman.jsonl"
            sessions = root / "sessions.jsonl"
            command = ["bash", str(Path(__file__).with_name("run.sh")), "--rpms", str(rpms),
                       "--stage", str(stage), "--work", str(root / "work"), *options]
            result = subprocess.run(command, capture_output=True, text=True, timeout=30,
                                    env={**os.environ, "PATH": str(tools) + os.pathsep + os.environ["PATH"],
                                         "PODMAN_CALLS": str(calls), "SESSION_CALLS": str(sessions),
                                         **({"PODMAN_IMAGES": "1"} if images else {})})
            recorded, started = ([json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []
                                 for path in (calls, sessions))
            return result, recorded, started

    def check_image(self, version, expected, override=None):
        result, recorded, _ = self.drive(version, *(["--image", override] if override else []))
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        images = [args[2] for args in recorded if args[:2] == ["image", "exists"]]
        self.assertEqual(images[0], expected)
        self.assertTrue(all(image in (expected, expected + "-pf1") for image in images))
        builds = [args for args in recorded if args[0] == "build"]
        self.assertEqual(len(builds), 1)
        self.assertEqual(builds[0][builds[0].index("-t") + 1], expected + "-build")
        self.assertIn(f"PLASMA={version}*", builds[0])
        self.assertFalse(any(args[0] == "run" for args in recorded))

    def test_675_uses_matching_stock_image(self):
        self.check_image("6.7.5", "localhost/plasma-fusion-test:f44-6.7.5")

    def test_682_uses_matching_stock_image(self):
        self.check_image("6.8.2", "localhost/plasma-fusion-test:f44-6.8.2")

    def test_683_uses_matching_stock_image(self):
        self.check_image("6.8.3", "localhost/plasma-fusion-test:f44-6.8.3")

    def test_explicit_image_is_preserved(self):
        self.check_image("6.8.2", "localhost/custom:stock", override="localhost/custom:stock")

    def test_kwin_68_sessions_without_gpu_get_the_software_render_device(self):
        # KWin 6.8 does not start without a render device: without the host's render node (--no-gpu,
        # as on GitHub's runners) its sessions get the software one (udmabuf). KWin 6.7.5 paints
        # with QPainter there, and with the render node a session needs nothing else.
        for version, options, software in (("6.7.5", ["--no-gpu"], "0"), ("6.8.2", ["--no-gpu"], "1"),
                                           ("6.8.3", ["--no-gpu"], "1"), ("6.8.3", [], "0")):
            with self.subTest(version=version, options=options):
                result, _, started = self.drive(version, *options, images=True)
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                # Two scenarios on each of the two lanes.
                self.assertEqual(len(started), 4, started)
                for args in started:
                    self.assertTrue(args[args.index("bash") + 1].endswith("/tools/vsession/cvsession.sh"), args)
                    self.assertIn("PFV_DRI=" + ("0" if options else "1"), args)
                    self.assertIn(f"PFV_SOFTWARE_DEVICE={software}", args)


if __name__ == "__main__":
    unittest.main()
