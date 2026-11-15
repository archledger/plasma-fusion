#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Offline checks: python3 -m unittest discover -s packaging/patches/kwin -v."""

import datetime
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from prepare_spec import prepare

# By path: the restricted runs below have an empty PATH.
BASH = shutil.which("bash")


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
        # 6.7.5 has no startup-flags patch, so its entry names none.
        self.assertIn("- 6.7.5-1.fc44.pf1\n- Expose requestedGeometry to scripts (KDE MR !10225)\n\n* Sat", result)
        self.assertTrue(result.endswith(SPEC[SPEC.index("* Sat"):]))

    def test_preserves_existing_patches(self):
        original = SPEC.replace("Source0:", "Patch1: fedora.patch\nSource0:")
        result = self.prepare(original)
        self.assertIn("Patch1: fedora.patch\n", result)
        self.assertIn("Patch9001:", result)

    def test_supports_fedora_682_without_changing_existing_spec_sections(self):
        original = SPEC.replace("Version: 6.7.5", "Version: 6.8.2").replace(
            "Release: 1%{?dist}", "Release: 3%{?dist}")
        original = original.replace("Source0:", "Patch0: fedora.patch\nSource0:")
        result = prepare(original, "6.8.2-3.fc44", datetime.date(2026, 11, 9))
        self.assertIn("Version: 6.8.2\n", result)
        self.assertIn("Release: 3%{?dist}.pf1\n", result)
        self.assertIn("Patch0: fedora.patch\n", result)
        self.assertIn("Patch9001: 0001-window-expose-requested-geometry-6.8.2.patch\n", result)
        self.assertIn("Patch9002: 0002-initialize-startup-flags-6.8.2.patch\n", result)
        self.assertIn("%prep\n%autosetup -p1\n", result)
        self.assertIn("- 6.8.2-3.fc44.pf1\n", result)
        self.assertIn("- 6.8.2-3.fc44.pf1\n- Expose requestedGeometry to scripts (KDE MR !10225)\n"
                      "- Initialize startup flags before their first read\n\n* Sat", result)
        self.assertTrue(result.endswith(original[original.index("* Sat"):]))

    def test_supports_fedora_683_with_the_682_patches(self):
        # Fedora's 6.8.3-1 has no patch of its own. 6.8.3 changed none of the files the two 6.8.2
        # patches change, so the build takes those two files and names both changes.
        original = SPEC.replace("Version: 6.7.5", "Version: 6.8.3")
        result = prepare(original, "6.8.3-1.fc44", datetime.date(2026, 11, 15))
        self.assertIn("Version: 6.8.3\n", result)
        self.assertIn("Release: 1%{?dist}.pf1\n", result)
        self.assertIn("Patch9001: 0001-window-expose-requested-geometry-6.8.2.patch\n"
                      "Patch9002: 0002-initialize-startup-flags-6.8.2.patch\n", result)
        self.assertIn("%prep\n%autosetup -p1\n", result)
        self.assertIn("- 6.8.3-1.fc44.pf1\n- Expose requestedGeometry to scripts (KDE MR !10225)\n"
                      "- Initialize startup flags before their first read\n\n* Sat", result)
        self.assertTrue(result.endswith(original[original.index("* Sat"):]))

    def test_68_target_requires_matching_spec_version(self):
        for version, release in (("6.8.2", "3"), ("6.8.3", "1")):
            vr = f"{version}-{release}.fc44"
            with self.subTest(vr=vr), self.assertRaisesRegex(ValueError, "mismatched spec"):
                prepare(SPEC.replace("Release: 1%{?dist}", f"Release: {release}%{{?dist}}"),
                        vr, datetime.date(2026, 11, 9))

    def test_rejects_unqualified_68_targets(self):
        for version, release in (("6.8.1", "3"), ("6.8.4", "1")):
            vr = f"{version}-{release}.fc44"
            matching = SPEC.replace("Version: 6.7.5", f"Version: {version}").replace(
                "Release: 1%{?dist}", f"Release: {release}%{{?dist}}")
            with self.subTest(vr=vr), self.assertRaises(ValueError):
                prepare(matching, vr, datetime.date(2026, 11, 9))

    def test_rejects_other_distribution_for_682(self):
        matching = SPEC.replace("Version: 6.7.5", "Version: 6.8.2").replace(
            "Release: 1%{?dist}", "Release: 3%{?dist}")
        with self.assertRaises(ValueError):
            prepare(matching, "6.8.2-3.fc45", datetime.date(2026, 11, 9))

    def test_68_rejects_reserved_second_patch(self):
        for version in ("6.8.2", "6.8.3"):
            original = SPEC.replace("Version: 6.7.5", f"Version: {version}")
            for tag in ("Patch9002", "Patch09002"):
                with self.subTest(version=version, tag=tag), self.assertRaisesRegex(ValueError, "already present"):
                    prepare(original.replace("Source0:", f"{tag}: existing.patch\nSource0:"),
                            f"{version}-1.fc44", datetime.date(2026, 11, 9))

    def test_675_preserves_unreserved_second_patch(self):
        original = SPEC.replace("Source0:", "Patch9002: existing.patch\nSource0:")
        self.assertIn("Patch9002: existing.patch\n", self.prepare(original))

    def test_rejects_existing_startup_patch(self):
        for version in ("6.8.2", "6.8.3"):
            original = SPEC.replace("Version: 6.7.5", f"Version: {version}").replace(
                "Source0:", "Patch7: 0002-initialize-startup-flags-6.8.2.patch\nSource0:")
            with self.subTest(version=version), self.assertRaisesRegex(ValueError, "already present"):
                prepare(original, f"{version}-1.fc44", datetime.date(2026, 11, 9))

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
            for vr in ("6.8.0-1.fc44", "6.8.4-1.fc44"):
                with self.subTest(builder=builder, vr=vr), tempfile.TemporaryDirectory() as temporary:
                    output = Path(temporary) / "output"
                    result = subprocess.run(
                        ["bash", str(Path(__file__).with_name(builder)), str(output), vr],
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

    def test_68_builders_reach_output_preservation_check(self):
        for vr in ("6.8.2-3.fc44", "6.8.3-1.fc44"):
            for builder, flags in (("build.sh", []), ("native-tests.sh", []), ("native-tests.sh", ["--stock"])):
                with self.subTest(vr=vr, builder=builder, flags=flags), tempfile.TemporaryDirectory() as temporary:
                    sentinel = Path(temporary) / ".existing-evidence"
                    sentinel.write_text("preserve this")
                    result = subprocess.run(
                        ["bash", str(Path(__file__).with_name(builder)), *flags, temporary, vr],
                        capture_output=True, text=True, check=False, timeout=10,
                    )
                    self.assertEqual(result.returncode, 64, result.stderr)
                    self.assertIn("output directory must be empty", result.stderr)
                    self.assertEqual(sentinel.read_text(), "preserve this")

    def test_native_tests_give_kwin_68_a_render_device(self):
        # KWin 6.8 does not start without a render device. native-tests.sh hands the one it selects
        # to the container, or stops (status 3) before starting one where it finds none: on a host
        # without a device, or in the containers that run this suite, which lack the selection
        # helper. 6.7.5 gets none. The container command is a stand-in that records its arguments.
        for vr in ("6.7.5-1.fc44", "6.8.2-3.fc44", "6.8.3-1.fc44"):
            with self.subTest(vr=vr), tempfile.TemporaryDirectory() as temporary:
                tools = Path(temporary) / "bin"
                tools.mkdir()
                podman = tools / "podman"
                podman.write_text('#!/bin/sh\nprintf "%s\\n" "$@" > "$PODMAN_ARGS"\n')
                podman.chmod(0o755)
                calls = Path(temporary) / "podman.args"
                result = subprocess.run(
                    ["bash", str(Path(__file__).with_name("native-tests.sh")), str(Path(temporary) / "output"), vr],
                    capture_output=True, text=True, check=False, timeout=10,
                    env={**os.environ, "PATH": f"{tools}{os.pathsep}{os.environ['PATH']}",
                         "PODMAN_ARGS": str(calls), "PFV_DRI": "0"},
                )
                if vr.startswith("6.7."):
                    args = calls.read_text().splitlines()
                    self.assertNotIn("--device", args)
                    self.assertIn("PFV_RENDER_DEVICE=", args)
                elif calls.exists():
                    args = calls.read_text().splitlines()
                    self.assertIn("--device", args)
                    device = args[args.index("--device") + 1].split(":")[0]
                    self.assertTrue(device, args)
                    self.assertIn(f"PFV_RENDER_DEVICE={device}", args)
                else:
                    self.assertEqual(result.returncode, 3, result.stderr)

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
            "build-in-container.sh": ([], ["6.8.0-1.fc44"], ["6.8.4-1.fc44"], ["6.7.5-1.fc44", "extra"]),
            "native-tests-in-container.sh": (
                [], ["6.7.5-1.fc44"], ["6.8.0-1.fc44", "backport"], ["6.8.4-1.fc44", "stock"],
                ["6.7.5-1.fc44", "other"], ["6.7.5-1.fc44", "stock", "extra"],
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

    def test_container_entry_points_accept_supported_targets(self):
        # Past its version check an entry point must stop before it changes anything: a restricted
        # shell (bash -r) refuses every redirection that opens a file, and an empty PATH finds no
        # command. The build then stops at its first output, the dependency log. The native tests
        # stop on KWin 6.8 because no render device was passed in (native-tests.sh passes it), and
        # on 6.7.5, which needs none, at their first output.
        written = "restricted: cannot redirect output"
        device = "requires an explicit render device"
        cases = (
            ("build-in-container.sh", ["6.7.5-1.fc44"], 1, written),
            ("build-in-container.sh", ["6.8.2-3.fc44"], 1, written),
            ("build-in-container.sh", ["6.8.3-1.fc44"], 1, written),
            ("native-tests-in-container.sh", ["6.7.5-1.fc44", "backport"], 3, written),
            ("native-tests-in-container.sh", ["6.8.2-3.fc44", "backport"], 3, device),
            ("native-tests-in-container.sh", ["6.8.3-1.fc44", "backport"], 3, device),
            ("native-tests-in-container.sh", ["6.8.3-1.fc44", "stock"], 3, device),
        )
        with tempfile.TemporaryDirectory() as empty:
            for entry, args, status, message in cases:
                with self.subTest(entry=entry, args=args):
                    result = subprocess.run(
                        [BASH, "-r", str(Path(__file__).with_name(entry)), *args],
                        capture_output=True, text=True, check=False, timeout=10, env={"PATH": empty},
                    )
                    self.assertEqual(result.returncode, status, result.stderr)
                    self.assertIn(message, result.stderr)


if __name__ == "__main__":
    unittest.main()
