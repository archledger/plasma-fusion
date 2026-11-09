#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Check image selection through the real driver, stopping before any container is built."""

import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class ImageSelectionTest(unittest.TestCase):
    def check_image(self, version, expected, override=None):
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
                'if command in ("image", "build"): sys.exit(1)\n'
                'sys.exit(91)\n')
            podman.chmod(0o755)
            calls = root / "podman.jsonl"
            command = ["bash", str(Path(__file__).with_name("run.sh")), "--rpms", str(rpms),
                       "--stage", str(stage), "--work", str(root / "work")]
            if override:
                command.extend(["--image", override])
            result = subprocess.run(command, capture_output=True, text=True, timeout=30,
                                    env={**os.environ, "PATH": str(tools) + os.pathsep + os.environ["PATH"],
                                         "PODMAN_CALLS": str(calls)})
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            recorded = [json.loads(line) for line in calls.read_text().splitlines()]
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

    def test_explicit_image_is_preserved(self):
        self.check_image("6.8.2", "localhost/custom:stock", override="localhost/custom:stock")


if __name__ == "__main__":
    unittest.main()
