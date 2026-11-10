# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Render-device selection and open failures without changing host device permissions."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


HELPER = Path(__file__).resolve().parents[3] / "tools/vsession/render-device.sh"
CVSESSION = HELPER.with_name("cvsession.sh")


class RenderDeviceTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)

    def device(self, name):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.symlink_to("/dev/null")
        return path

    def select(self, mode):
        return subprocess.run(["bash", "-euo", "pipefail", "-c",
                               'source "$1"; pfv_render_device "$2" "$3"', "test",
                               str(HELPER), mode, str(self.root)], capture_output=True, text=True, timeout=10)

    def test_absent_dri_directory_uses_software_device(self):
        device = self.device("udmabuf")
        result = self.select("auto")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), str(device))

    def test_hardware_is_preferred(self):
        device = self.device("dri/renderD128")
        self.device("udmabuf")
        result = self.select("auto")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), str(device))

    def test_software_mode_excludes_hardware(self):
        self.device("dri/renderD128")
        self.assertNotEqual(self.select("software").returncode, 0)
        device = self.device("udmabuf")
        self.assertEqual(self.select("software").stdout.strip(), str(device))

    def test_regular_file_is_not_a_device(self):
        (self.root / "udmabuf").touch()
        self.assertNotEqual(self.select("auto").returncode, 0)

    def test_successful_open_is_reported(self):
        device = self.device("udmabuf")
        result = subprocess.run(["bash", str(HELPER), "--check", str(device)],
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("opened render device", result.stdout)

    def test_denied_open_fails_even_when_device_exists(self):
        device = self.device("udmabuf")
        result = subprocess.run(["bash", "-euo", "pipefail", "-c",
                                'source "$1"; exec() { return 1; }; pfv_check_render_device "$2"',
                                "test", str(HELPER), str(device)],
                                capture_output=True, text=True, timeout=10)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("cannot open render device", result.stderr)

    def test_container_failure_is_not_reported_as_success(self):
        tools = self.root / "bin"
        tools.mkdir()
        podman = tools / "podman"
        podman.write_text('#!/bin/sh\ncase "$1" in unshare) exit 0;; run) exit 7;; *) exit 99;; esac\n')
        podman.chmod(0o755)
        seed = self.root / "seed"
        seed.mkdir()
        scenario = self.root / "scenario.sh"
        scenario.write_text('exit 99\n')
        result = subprocess.run(["bash", str(CVSESSION), "device-test", str(scenario), str(seed)],
                                cwd=self.root, capture_output=True, text=True, timeout=10,
                                env={**os.environ, "PATH": str(tools) + os.pathsep + os.environ["PATH"],
                                     "PFV_DRI": "0", "PFV_SOFTWARE_DEVICE": "0"})
        self.assertEqual(result.returncode, 7, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
