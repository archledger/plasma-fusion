#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Offline checks: python3 -m unittest discover -s packaging/patches/kwin -v."""

import datetime
from pathlib import Path
import subprocess
import tempfile
import unittest

from prepare_spec import prepare


SPEC = """Name:    kwin
Version: 6.7.5
Release: 1%{?dist}
Summary: KDE Window manager
License: GPL-2.0-or-later
Source0: kwin-%{version}.tar.xz
%description
A compositor.
%prep
%autosetup -p1
%build
%changelog
* Sat Oct 03 2026 Example Maintainer <maintainer@example.org> - 6.7.5-1
- Original entry
"""


class PrepareSpecTest(unittest.TestCase):
    def prepare(self, text=SPEC):
        return prepare(text, "6.7.5-1.fc44", datetime.date(2026, 10, 26))

    def test_no_existing_patches(self):
        result = self.prepare()
        self.assertIn("Release: 1%{?dist}.pf1\n", result)
        self.assertIn("Patch9001: 0001-window-expose-requested-geometry.patch\n", result)
        self.assertLess(result.index("Patch9001:"), result.index("%description"))
        self.assertIn("%prep\n%autosetup -p1\n", result)
        self.assertIn("- 6.7.5-1.fc44.pf1\n", result)
        self.assertTrue(result.endswith(SPEC[SPEC.index("* Sat"):]))

    def test_preserves_existing_patches(self):
        original = SPEC.replace("Source0:", "Patch1: fedora.patch\nSource0:")
        result = self.prepare(original)
        self.assertIn("Patch1: fedora.patch\n", result)
        self.assertIn("Patch9001:", result)

    def test_rejects_incompatible_specs(self):
        for old, new in (
            ("Name:    kwin", "Name:    plasma-workspace"),
            ("Version: 6.7.5", "Version: 6.8.0"),
            ("Release: 1%{?dist}", "Release: 2%{?dist}"),
            ("Release: 1%{?dist}", "Release: 1%{?dist}.pf1"),
            ("%autosetup -p1", "%setup -q"),
            ("%changelog", "%autochangelog"),
            ("Source0:", "Patch9001: other.patch\nSource0:"),
            ("Source0:", "Patch7: 0001-window-expose-requested-geometry.patch\nSource0:"),
        ):
            with self.subTest(new=new), self.assertRaises(ValueError):
                self.prepare(SPEC.replace(old, new))

    def test_rejects_other_targets(self):
        for vr in ("6.8.0-1.fc44", "6.7.5-1.fc45", "6.7.5-1.fc44.pf1", "../kwin"):
            with self.subTest(vr=vr), self.assertRaises(ValueError):
                prepare(SPEC, vr, datetime.date(2026, 10, 26))

    # The package build and the native test build check their target and output alike.
    BUILDERS = ("build.sh", "native-tests.sh")

    def test_builder_rejects_other_target_before_creating_output(self):
        for builder in self.BUILDERS:
            with self.subTest(builder=builder), tempfile.TemporaryDirectory() as temporary:
                output = Path(temporary) / "output"
                result = subprocess.run(
                    ["bash", str(Path(__file__).with_name(builder)), str(output), "6.8.0-1.fc44"],
                    capture_output=True, text=True, check=False,
                )
                self.assertEqual(result.returncode, 64, result.stderr)
                self.assertFalse(output.exists())

    def test_builder_does_not_overwrite_existing_output(self):
        for builder in self.BUILDERS:
            with self.subTest(builder=builder), tempfile.TemporaryDirectory() as temporary:
                sentinel = Path(temporary) / ".existing-evidence"
                sentinel.write_text("preserve this")
                result = subprocess.run(
                    ["bash", str(Path(__file__).with_name(builder)), temporary, "6.7.5-1.fc44"],
                    capture_output=True, text=True, check=False,
                )
                self.assertEqual(result.returncode, 64, result.stderr)
                self.assertEqual(sentinel.read_text(), "preserve this")

    def test_stock_tests_reject_other_target_before_creating_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "output"
            result = subprocess.run(
                ["bash", str(Path(__file__).with_name("native-tests.sh")), "--stock", str(output), "6.8.0-1.fc44"],
                capture_output=True, text=True, check=False,
            )
            self.assertEqual(result.returncode, 64, result.stderr)
            self.assertFalse(output.exists())

    def test_container_entry_points_reject_other_targets(self):
        cases = {
            "build-in-container.sh": ([], ["6.8.0-1.fc44"], ["6.7.5-1.fc44", "extra"]),
            "native-tests-in-container.sh": (
                [], ["6.7.5-1.fc44"], ["6.8.0-1.fc44", "backport"], ["6.7.5-1.fc44", "other"],
                ["6.7.5-1.fc44", "stock", "extra"],
            ),
        }
        for entry, arg_lists in cases.items():
            for args in arg_lists:
                with self.subTest(entry=entry, args=args):
                    result = subprocess.run(
                        ["bash", str(Path(__file__).with_name(entry)), *args],
                        capture_output=True, text=True, check=False,
                    )
                    self.assertEqual(result.returncode, 64, result.stderr)


if __name__ == "__main__":
    unittest.main()
