#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""P0 safety/receipt checks; event-handler tests also require the repository's Node.js tool."""

import hashlib
import importlib.util
import json
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock
from xml.etree import ElementTree

if __package__:
    from .cleanup_tests import CleanupGateTests as CleanupGateTests
    from .cleanup_tests import CleanupOwnershipTests as CleanupOwnershipTests
    from .cleanup_tests import CleanupSeedTests as CleanupSeedTests
    from .cleanup_tests import write_cleanup_fixture
    from .consumer_lifecycle_tests import ConsumerLifecycleTests as ConsumerLifecycleTests
    from .mixed_lifetime_tests import MixedLifetimeSeedTests as MixedLifetimeSeedTests
    from .mixed_lifetime_tests import MixedLifetimePublicationTests as MixedLifetimePublicationTests
    from .mixed_lifetime_tests import MixedLifetimeReceiptTests as MixedLifetimeReceiptTests
    from .mixed_lifetime_tests import MixedLifetimeSnapshotTests as MixedLifetimeSnapshotTests
    from .qml_helpers import qml_handler
    # Re-export preserves the existing unittest entry point and class selectors.
    from .target_guard_tests import TargetGuardTests as TargetGuardTests
    from .view_loss_tests import ViewLossCheckerTests as ViewLossCheckerTests
    from .view_loss_tests import ViewLossSeedTests as ViewLossSeedTests
    from .view_loss_tests import ViewLossTraceTests as ViewLossTraceTests
else:
    from cleanup_tests import CleanupGateTests as CleanupGateTests
    from cleanup_tests import CleanupOwnershipTests as CleanupOwnershipTests
    from cleanup_tests import CleanupSeedTests as CleanupSeedTests
    from cleanup_tests import write_cleanup_fixture
    from consumer_lifecycle_tests import ConsumerLifecycleTests as ConsumerLifecycleTests
    from mixed_lifetime_tests import MixedLifetimeSeedTests as MixedLifetimeSeedTests
    from mixed_lifetime_tests import MixedLifetimePublicationTests as MixedLifetimePublicationTests
    from mixed_lifetime_tests import MixedLifetimeReceiptTests as MixedLifetimeReceiptTests
    from mixed_lifetime_tests import MixedLifetimeSnapshotTests as MixedLifetimeSnapshotTests
    from qml_helpers import qml_handler
    from target_guard_tests import TargetGuardTests as TargetGuardTests
    from view_loss_tests import ViewLossCheckerTests as ViewLossCheckerTests
    from view_loss_tests import ViewLossSeedTests as ViewLossSeedTests
    from view_loss_tests import ViewLossTraceTests as ViewLossTraceTests

PREPARER = Path(__file__).with_name("prepare_seed.py")
LIFECYCLE = Path(__file__).with_name("lifecycle.py")




class SeedTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix="pf-layout-seed-", dir="/tmp/opencode")
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)
        self.stage = self.root / "build/stage"
        self.rules = self.stage / ".local/share/kwin/scripts/plasmafusion-placement/contents/ui/Tiling.js"
        self.rules.parent.mkdir(parents=True)
        self.rules.write_text("// exact staged tiling rules\n")
        self.output = self.root / "build/seed"

    def run_seed(self, *extra_args):
        return subprocess.run(
            [sys.executable, str(PREPARER), "--stage", str(self.stage),
             "--output", str(self.output), *extra_args],
            cwd=self.root, capture_output=True, text=True, timeout=10, check=False,
        )

    def test_creates_only_private_probe_packages(self):
        result = self.run_seed()
        self.assertEqual(result.returncode, 0, result.stderr)
        script = self.output / ".local/share/kwin/scripts/plasmafusion-layout-probe"
        applet = self.output / ".local/share/plasma/plasmoids/org.plasmafusion.layoutprobe"
        self.assertEqual(json.loads((script / "metadata.json").read_text())["KPlugin"]["Id"],
                         "plasmafusion-layout-probe")
        self.assertEqual((script / "contents/ui/Tiling.js").read_bytes(), self.rules.read_bytes())
        self.assertTrue((applet / "contents/config/main.xml").is_file())
        self.assertIn("plasmafusion-layout-probeEnabled=true", (self.output / ".config/kwinrc").read_text())
        self.assertIn("ProbeAuthorized=true", (self.output / ".config/kwinrc").read_text())
        self.assertIn("DropRetirementFrame=false", (self.output / ".config/kwinrc").read_text())
        self.assertIn("ReplyDelayMs=0", (self.output / ".config/kwinrc").read_text())
        self.assertIn("FocusProbe=false", (self.output / ".config/kwinrc").read_text())
        self.assertEqual(self.query_timeout_default(), 10000)
        self.assertFalse((self.output / ".config/plasma-org.kde.plasma.desktop-appletsrc").exists())

    def test_refuses_an_existing_seed_without_overwriting_it(self):
        self.output.mkdir()
        sentinel = self.output / "sentinel"
        sentinel.write_text("keep this evidence")
        result = self.run_seed()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("already exists", result.stderr)
        self.assertEqual(sentinel.read_text(), "keep this evidence")
        self.assertEqual(list(self.output.iterdir()), [sentinel])

    def test_refuses_an_output_outside_the_private_build_directory(self):
        self.output = self.root / ".config"
        result = self.run_seed()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("under the current worktree's build directory", result.stderr)
        self.assertFalse(self.output.exists())

    def test_missing_stage_leaves_no_partial_seed(self):
        self.rules.unlink()
        result = self.run_seed()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("staged Tiling.js", result.stderr)
        self.assertFalse(self.output.exists())

    def run_check(self, *extra_args):
        return subprocess.run(
            [sys.executable, str(PREPARER), "--check-result", str(self.output), *extra_args],
            cwd=self.root, capture_output=True, text=True, timeout=10, check=False,
        )

    def result_files(self, session_status=0):
        self.output.mkdir()
        (self.output / "scenario.log").write_text(f"scenario rc=0\nsession rc={session_status}\n")
        (self.output / "container.log").write_text("session rc=0\n")
        (self.output / "layout-probe-result.json").write_text(json.dumps({
            "schema": 1, "passed": True, "checks": ["roundtrip-native", "retirement"],
        }))
        write_cleanup_fixture(self.output)

    def test_result_check_rejects_outer_zero_with_failed_scenario(self):
        self.result_files(session_status=1)
        result = self.run_check()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("scenario did not finish successfully", result.stderr)

    def test_result_check_requires_explicit_receipt(self):
        self.result_files()
        (self.output / "layout-probe-result.json").unlink()
        result = self.run_check()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("missing probe receipt", result.stderr)

    def test_result_check_rejects_incomplete_checks(self):
        self.result_files()
        (self.output / "layout-probe-result.json").write_text(json.dumps({
            "schema": 1, "passed": True, "checks": ["roundtrip-native"],
        }))
        result = self.run_check()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("incomplete probe receipt", result.stderr)

    def test_result_check_accepts_a_complete_success(self):
        self.result_files()
        result = self.run_check()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_retirement_frame_fault_is_an_explicit_private_seed_setting(self):
        result = self.run_seed("--drop-retirement-frame")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("DropRetirementFrame=true", (self.output / ".config/kwinrc").read_text())

    def test_seed_manifest_covers_the_fault_setting(self):
        result = self.run_seed()
        self.assertEqual(result.returncode, 0, result.stderr)
        inputs = json.loads((self.output / "probe-inputs.json").read_text())
        self.assertEqual(inputs["kwinrc"], hashlib.sha256(
            (self.output / ".config/kwinrc").read_bytes()
        ).hexdigest())

    def test_loss_scope_does_not_accept_the_first_slice_receipt(self):
        self.result_files()
        result = self.run_check("--scope", "silent-retirement")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("missing probe receipt", result.stderr)

    def test_loss_scope_requires_its_own_explicit_receipt(self):
        self.result_files()
        (self.output / "silent-retirement-result.json").write_text(json.dumps({
            "schema": 1, "passed": True,
            "checks": ["roundtrip-native", "silent-retirement", "provider-reload"],
        }))
        result = self.run_check("--scope", "silent-retirement")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_result_scope_cannot_change_seed_preparation(self):
        result = self.run_seed("--scope", "silent-retirement")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("--scope requires --check-result", result.stderr)
        self.assertFalse(self.output.exists())

    def test_ordering_scope_does_not_accept_the_first_slice_receipt(self):
        self.result_files()
        result = self.run_check("--scope", "reply-ordering")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("missing probe receipt", result.stderr)

    def test_ordering_scope_accepts_its_own_complete_receipt(self):
        self.result_files()
        (self.output / "reply-ordering-result.json").write_text(json.dumps({
            "schema": 1, "passed": True,
            "checks": ["roundtrip-native", "same-provider-ordering"],
        }))
        result = self.run_check("--scope", "reply-ordering")
        self.assertEqual(result.returncode, 0, result.stderr)

    def query_timeout_default(self):
        schema = self.output / (
            ".local/share/plasma/plasmoids/org.plasmafusion.layoutprobe/contents/config/main.xml"
        )
        entry = ElementTree.parse(schema).find(
            ".//k:entry[@name='queryTimeoutMs']/k:default",
            {"k": "http://www.kde.org/standards/kcfg/1.0"},
        )
        self.assertIsNotNone(entry, "client query deadline missing from the private schema")
        return int(entry.text)

    def test_delayed_reply_fault_records_both_private_timing_inputs(self):
        result = self.run_seed("--query-timeout-ms", "200", "--reply-delay-ms", "2000")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.query_timeout_default(), 200)
        self.assertIn("ReplyDelayMs=2000", (self.output / ".config/kwinrc").read_text())

    def test_query_deadline_rejects_invalid_input_without_partial_seed(self):
        result = self.run_seed("--query-timeout-ms", "-1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("query deadline must", result.stderr)
        self.assertFalse(self.output.exists())

    def test_reply_delay_is_bounded_without_partial_seed(self):
        result = self.run_seed("--query-timeout-ms", "200", "--reply-delay-ms", "5000")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("reply delay must", result.stderr)
        self.assertFalse(self.output.exists())

    def test_late_reply_fault_must_exceed_the_query_deadline(self):
        result = self.run_seed("--query-timeout-ms", "200", "--reply-delay-ms", "100")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("reply delay must exceed", result.stderr)
        self.assertFalse(self.output.exists())

    def test_seed_manifest_covers_the_client_deadline_schema(self):
        result = self.run_seed()
        self.assertEqual(result.returncode, 0, result.stderr)
        schema = self.output / (
            ".local/share/plasma/plasmoids/org.plasmafusion.layoutprobe/contents/config/main.xml"
        )
        inputs = json.loads((self.output / "probe-inputs.json").read_text())
        self.assertEqual(inputs["main.xml"], hashlib.sha256(schema.read_bytes()).hexdigest())

    def test_receipt_check_cannot_enable_timing_faults(self):
        self.result_files()
        result = self.run_check("--query-timeout-ms", "200")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("cannot be combined", result.stderr)

    def test_timeout_scope_does_not_accept_other_receipts(self):
        self.result_files()
        result = self.run_check("--scope", "query-timeout-late")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("missing probe receipt", result.stderr)

    def test_timeout_scope_accepts_its_own_complete_receipt(self):
        self.result_files()
        (self.output / "query-timeout-result.json").write_text(json.dumps({
            "schema": 1, "passed": True,
            "checks": ["roundtrip-native", "query-timeout", "late-state"],
        }))
        result = self.run_check("--scope", "query-timeout-late")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_focus_observation_is_an_explicit_private_seed(self):
        result = self.run_seed("--focus-probe")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("FocusProbe=true", (self.output / ".config/kwinrc").read_text())
        helper = self.output / ".local/lib/layout-control/heldclient.py"
        self.assertEqual(helper.read_bytes(),
                         (PREPARER.parent.parent / "lib/heldclient.py").read_bytes())
        inputs = json.loads((self.output / "probe-inputs.json").read_text())
        self.assertEqual(inputs["heldclient.py"], hashlib.sha256(helper.read_bytes()).hexdigest())

    def test_focus_observation_does_not_enable_other_fault_modes(self):
        result = self.run_seed("--focus-probe", "--drop-retirement-frame")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("focus observation requires normal transport", result.stderr)
        self.assertFalse(self.output.exists())

    def test_focus_scope_requires_its_own_receipt(self):
        self.result_files()
        result = self.run_check("--scope", "focus-observation")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("missing probe receipt", result.stderr)

    def test_focus_scope_accepts_only_the_explicit_observation_receipt(self):
        self.result_files()
        (self.output / "focus-observation-result.json").write_text(json.dumps({
            "schema": 1, "passed": True,
            "checks": ["roundtrip-native", "panel-keyboard-focus"],
        }))
        result = self.run_check("--scope", "focus-observation")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_target_probe_is_a_separate_default_off_private_mode(self):
        result = self.run_seed("--target-probe")
        self.assertEqual(result.returncode, 0, result.stderr)
        config = (self.output / ".config/kwinrc").read_text()
        self.assertIn("FocusProbe=true", config)
        self.assertIn("TargetProbe=true", config)
        self.assertTrue((self.output / ".local/lib/layout-control/heldclient.py").is_file())

    def test_target_probe_cannot_stack_a_transport_fault(self):
        result = self.run_seed("--target-probe", "--drop-retirement-frame")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("focus observation requires normal transport", result.stderr)
        self.assertFalse(self.output.exists())

    def test_target_scope_requires_its_specific_receipt(self):
        self.result_files()
        result = self.run_check("--scope", "target-preparation")
        self.assertNotEqual(result.returncode, 0)
        (self.output / "target-preparation-result.json").write_text(json.dumps({
            "schema": 1, "passed": True, "checks": ["roundtrip-native", "guarded-target"],
        }))
        result = self.run_check("--scope", "target-preparation")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_consumer_scope_requires_its_specific_complete_receipt(self):
        self.result_files()
        result = self.run_check("--scope", "consumer-retirement")
        self.assertNotEqual(result.returncode, 0)
        receipt = self.output / "consumer-retirement-result.json"
        receipt.write_text(json.dumps({
            "schema": 1, "passed": True, "checks": ["roundtrip-native", "guarded-target"],
        }))
        result = self.run_check("--scope", "consumer-retirement")
        self.assertNotEqual(result.returncode, 0)
        receipt.write_text(json.dumps({
            "schema": 1, "passed": True, "checks": [
                "roundtrip-native", "guarded-target", "consumer-retirement",
                "busy-replay", "explicit-recovery",
            ],
        }))
        result = self.run_check("--scope", "consumer-retirement")
        self.assertEqual(result.returncode, 0, result.stderr)


class LifecycleSafetyTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix="pf-layout-lifecycle-", dir="/tmp/opencode")
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)
        self.seed = self.root / "build/seed"
        (self.seed / ".config").mkdir(parents=True)
        (self.seed / ".config/kwinrc").write_text(
            "[Script-plasmafusion-layout-probe]\nProbeAuthorized=true\n"
        )
        self.name = "layout-control-lc-unit"
        self.output = self.root / "vsession-out" / self.name
        self.image = "1" * 64
        spec = importlib.util.spec_from_file_location("layout_lifecycle", LIFECYCLE)
        self.runner = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.runner)

    def validate(self):
        self.runner.validate_run(self.seed, self.output, self.name, self.image, self.root)

    def test_refuses_mutable_image_tags(self):
        self.image = "localhost/pf-layout-probe:latest"
        with self.assertRaisesRegex(ValueError, "immutable image"):
            self.validate()

    def test_refuses_existing_results_without_touching_them(self):
        self.output.mkdir(parents=True)
        sentinel = self.output / "sentinel"
        sentinel.write_text("keep this evidence")
        with self.assertRaisesRegex(ValueError, "already exists"):
            self.validate()
        self.assertEqual(sentinel.read_text(), "keep this evidence")

    def test_refuses_seed_outside_the_private_build_tree(self):
        self.seed = self.root / ".config"
        with self.assertRaisesRegex(ValueError, "private build"):
            self.validate()

    def test_refuses_seed_symlinks(self):
        (self.seed / "outside").symlink_to(self.root)
        with self.assertRaisesRegex(ValueError, "symlink"):
            self.validate()

    def test_requires_the_private_authorization_marker(self):
        (self.seed / ".config/kwinrc").write_text("")
        with self.assertRaisesRegex(ValueError, "authorization"):
            self.validate()

    def test_refuses_an_unscoped_run_name(self):
        self.name = "another-session"
        with self.assertRaisesRegex(ValueError, "run name"):
            self.validate()

    def test_container_has_no_host_bus_network_or_added_privilege(self):
        self.validate()
        command = self.runner.container_command(self.seed, self.output, self.name, self.image)
        self.assertIn("--network=none", command)
        self.assertIn("--security-opt=no-new-privileges", command)
        self.assertNotIn("--privileged", command)
        self.assertFalse(any("cap-add" in value or "network=host" in value for value in command))
        self.assertFalse(any("/run/user/" in value or "DBUS_SESSION_BUS_ADDRESS=" in value
                             for value in command))
        self.assertIn("pf-" + self.name, command)

    def test_session_environment_never_inherits_a_live_bus_or_display(self):
        private = Path("/var/tmp/pfv-" + self.name)
        environment = self.runner.session_environment(private)
        self.assertEqual(environment["HOME"], str(private / "home"))
        self.assertEqual(environment["XDG_RUNTIME_DIR"], str(private / "run"))
        self.assertEqual(environment["WAYLAND_DISPLAY"], "w0")
        self.assertNotIn("DBUS_SESSION_BUS_ADDRESS", environment)
        self.assertNotIn("DBUS_SYSTEM_BUS_ADDRESS", environment)
        self.assertNotIn("DISPLAY", environment)

    def test_cli_rejects_unscoped_input_without_launching_anything(self):
        result = subprocess.run(
            [sys.executable, str(LIFECYCLE), "--name", "another-session",
             "--seed", str(self.seed), "--image", self.image],
            cwd=self.root, capture_output=True, text=True, timeout=10, check=False,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("run name", result.stderr)
        self.assertFalse(self.output.exists())

    def test_lifecycle_receipt_rejects_success_without_process_replacement(self):
        receipt = {"schema": 1, "passed": True, "scope": "p0-private-bus", "busId": "a" * 32}
        with self.assertRaisesRegex(ValueError, "replacement"):
            self.runner.check_receipt(receipt)

    def test_lifecycle_receipt_requires_different_backend_connections(self):
        receipt = {
            "schema": 1, "scope": "p0-process-replacement", "passed": True,
            "busIds": ["a" * 32] * 3, "backendOwners": [":1.1", ":1.1"],
            "shellOwners": [":1.2", ":1.3", ":1.4"],
            "checks": ["private-bus", "shell-restart", "backend-restart"],
        }
        with self.assertRaisesRegex(ValueError, "backend connections"):
            self.runner.check_receipt(receipt)

    def test_lifecycle_receipt_rejects_a_replaced_bus(self):
        receipt = {
            "schema": 1, "scope": "p0-process-replacement", "passed": True,
            "busIds": ["a" * 32, "a" * 32, "b" * 32], "backendOwners": [":1.1", ":1.2"],
            "shellOwners": [":1.3", ":1.4", ":1.5"],
            "checks": ["private-bus", "shell-restart", "backend-restart"],
        }
        with self.assertRaisesRegex(ValueError, "same private bus"):
            self.runner.check_receipt(receipt)

    def test_lifecycle_receipt_accepts_the_complete_narrow_scope(self):
        receipt = {
            "schema": 1, "scope": "p0-process-replacement", "passed": True,
            "busIds": ["a" * 32] * 3, "backendOwners": [":1.1", ":1.2"],
            "shellOwners": [":1.3", ":1.4", ":1.5"],
            "checks": ["private-bus", "shell-restart", "backend-restart"],
        }
        self.runner.check_receipt(receipt)

    def test_session_mode_refuses_host_before_any_side_effect(self):
        private = Path("/var/tmp/pfv-" + self.name)
        environment = self.runner.session_environment(private) | {
            "DBUS_SESSION_BUS_ADDRESS": "unix:path=/run/user/1000/bus",
        }
        with (mock.patch.dict("os.environ", environment, clear=True),
              mock.patch.object(self.runner.os, "geteuid", return_value=1000),
              mock.patch.object(Path, "is_file", return_value=False),
              mock.patch.object(Path, "mkdir") as mkdir,
              mock.patch.object(Path, "write_text") as write,
              mock.patch.object(self.runner, "qdbus") as bus,
              mock.patch.object(self.runner.subprocess, "run",
                                side_effect=AssertionError("unsafe bus/process operation")) as launch):
            with self.assertRaisesRegex(ValueError, "disposable container"):
                self.runner.session_probe(self.name)
            mkdir.assert_not_called()
            write.assert_not_called()
            bus.assert_not_called()
            launch.assert_not_called()

    def test_owner_lookup_retries_a_disappearing_owner_only(self):
        absent = subprocess.CalledProcessError(
            1, ["qdbus-qt6"], stderr="Error: org.freedesktop.DBus.Error.NameHasNoOwner\n"
        )
        def reply(*arguments):
            if arguments[2] == "org.freedesktop.DBus.NameHasOwner":
                return "true"
            raise absent
        with mock.patch.object(self.runner, "qdbus", side_effect=reply) as query:
            self.assertEqual(self.runner.owner_of("org.kde.KWin"), "")
            self.assertEqual(query.call_count, 1)

    def test_owner_lookup_retains_other_bus_failures(self):
        disconnected = subprocess.CalledProcessError(
            1, ["qdbus-qt6"], stderr="Error: org.freedesktop.DBus.Error.Disconnected\n"
        )
        with mock.patch.object(self.runner, "qdbus", side_effect=disconnected):
            with self.assertRaises(subprocess.CalledProcessError):
                self.runner.owner_of("org.kde.KWin")

    def test_owner_lookup_handles_the_real_qdbus_stdout_error(self):
        absent = subprocess.CalledProcessError(
            2, ["qdbus-qt6"],
            output="Error: org.freedesktop.DBus.Error.NameHasNoOwner\n",
            stderr="",
        )
        with mock.patch.object(self.runner, "qdbus", side_effect=absent):
            self.assertEqual(self.runner.owner_of("org.kde.KWin"), "")

    def test_owner_lookup_method_error_is_not_hidden_by_locale_stderr(self):
        absent = subprocess.CalledProcessError(
            2, ["qdbus-qt6"],
            output="Error: org.freedesktop.DBus.Error.NameHasNoOwner\nCould not get owner\n",
            stderr='Detected locale "C" with character encoding "ANSI_X3.4-1968", which is not UTF-8.\n'
                   'Qt depends on a UTF-8 locale, and has switched to "C.UTF-8" instead.\n',
        )
        with mock.patch.object(self.runner, "qdbus", side_effect=absent):
            self.assertEqual(self.runner.owner_of("org.kde.plasmashell"), "")

    def test_owner_lookup_does_not_override_unexpected_method_error_with_stderr(self):
        denied = subprocess.CalledProcessError(
            2, ["qdbus-qt6"],
            output="Error: org.freedesktop.DBus.Error.AccessDenied\n",
            stderr="Error: org.freedesktop.DBus.Error.NameHasNoOwner\n",
        )
        with mock.patch.object(self.runner, "qdbus", side_effect=denied):
            with self.assertRaises(subprocess.CalledProcessError):
                self.runner.owner_of("org.kde.plasmashell")

    def test_owner_lookup_never_accepts_a_signal_terminated_method_error(self):
        crashed = subprocess.CalledProcessError(
            -6, ["qdbus-qt6"],
            output="Error: org.freedesktop.DBus.Error.NameHasNoOwner\n",
            stderr="Aborted (core dumped)\n",
        )
        with mock.patch.object(self.runner, "qdbus", side_effect=crashed):
            with self.assertRaises(subprocess.CalledProcessError):
                self.runner.owner_of("org.kde.plasmashell")

    def test_owner_lookup_uses_one_authoritative_query(self):
        with mock.patch.object(self.runner, "qdbus", return_value=":1.42") as query:
            self.assertEqual(self.runner.owner_of("org.kde.KWin"), ":1.42")
            query.assert_called_once_with("org.freedesktop.DBus", "/org/freedesktop/DBus",
                                          "org.freedesktop.DBus.GetNameOwner", "org.kde.KWin")


class OwnerEventTests(unittest.TestCase):
    def run_event(self, *, checking=None, bound=True, wrapped=False, service=None):
        handler = qml_handler("dbusNameOwnerChanged")
        identity = "org.plasmafusion.LayoutProbe.ptest"
        probe = {
            "stopped": False, "boundOwner": ":1.0" if bound else "",
            "boundIdentity": identity if bound else "", "checkingPacket": checking,
            "requestNumber": 3, "phase": "online" if bound else "unknown",
        }
        values = [service or identity, ":1.0", ""]
        script = "const probe=" + json.dumps(probe) + ";\n"
        script += ("probe.freshQuery = showUnknown => { ++probe.requestNumber;"
                   "if(showUnknown) probe.phase='unknown'; };\nconsole.info = () => {};\n")
        script += handler + "\nconst values=" + json.dumps(values) + ";\n"
        script += ("dbusNameOwnerChanged(...values.map(value => ({toString: () => value})));\n"
                   if wrapped else "dbusNameOwnerChanged(...values);\n")
        script += "process.stdout.write(JSON.stringify([probe.phase,probe.requestNumber]));\n"
        result = subprocess.run(["node", "-"], input=script, capture_output=True, text=True,
                                timeout=10, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_signal_decodes_workspace_string_wrappers(self):
        self.assertEqual(self.run_event(wrapped=True), ["unknown", 4])

    def test_loss_during_unbound_current_verification_invalidates(self):
        packet = {"request": 3, "backendOwner": ":1.0",
                  "identityName": "org.plasmafusion.LayoutProbe.ptest"}
        self.assertEqual(self.run_event(checking=packet, bound=False), ["unknown", 4])

    def test_stale_verification_cannot_invalidate_a_new_query(self):
        packet = {"request": 2, "backendOwner": ":1.0",
                  "identityName": "org.plasmafusion.LayoutProbe.ptest"}
        self.assertEqual(self.run_event(checking=packet, bound=False), ["unknown", 3])

    def test_unrelated_name_loss_keeps_the_binding(self):
        self.assertEqual(self.run_event(service="org.example.Unrelated"), ["online", 3])

    def test_watched_backend_loss_invalidates(self):
        self.assertEqual(self.run_event(service="org.kde.KWin"), ["unknown", 4])


class ReplyOrderingTests(unittest.TestCase):
    @staticmethod
    def packet(revision: int, *, epoch: str = "a" * 32, request: int = 3):
        return {
            "consumer": "current", "request": request, "epoch": epoch, "revision": revision,
            "backendOwner": ":1.0", "identityName": "org.plasmafusion.LayoutProbe.p" + epoch,
            "status": "online", "capable": True,
        }

    def run_packets(self, packets):
        # Keep native verification busy; live tests exercise the actual asynchronous boundary.
        script = ("const probe={stopped:false,boot:'current',requestNumber:3,"
                  "verifying:true,pendingPacket:null};"
                  "probe.verifyPending=()=>{};console.info=()=>{};"
                  "const Plasmoid={configuration:{layoutResponse:''}};\n")
        script += qml_handler("onLayoutResponseChanged")
        script += "\nfor(const packet of " + json.dumps(packets) + ") {"
        script += ("Plasmoid.configuration.layoutResponse=JSON.stringify(packet);"
                   "onLayoutResponseChanged();}"
                   "process.stdout.write(JSON.stringify(probe.pendingPacket));\n")
        result = subprocess.run(["node", "-"], input=script, capture_output=True, text=True,
                                timeout=10, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_newest_pending_state_survives_a_delayed_older_reply(self):
        queued = self.run_packets([self.packet(100), self.packet(90)])
        self.assertEqual(queued["revision"], 100)

    def test_newer_reply_replaces_an_older_pending_state(self):
        queued = self.run_packets([self.packet(90), self.packet(100)])
        self.assertEqual(queued["revision"], 100)

    def test_revision_watermark_does_not_hide_another_provider_epoch(self):
        queued = self.run_packets([self.packet(100), self.packet(1, epoch="b" * 32)])
        self.assertEqual(queued["epoch"], "b" * 32)
        self.assertEqual(queued["revision"], 1)

    def test_other_backend_owner_is_not_hidden_by_the_pending_watermark(self):
        replacement = self.packet(1) | {"backendOwner": ":1.99"}
        queued = self.run_packets([self.packet(100), replacement])
        self.assertEqual(queued["backendOwner"], ":1.99")
        self.assertEqual(queued["revision"], 1)

    def test_stale_request_cannot_replace_current_pending_state(self):
        queued = self.run_packets([self.packet(100), self.packet(200, request=2)])
        self.assertEqual(queued["request"], 3)
        self.assertEqual(queued["revision"], 100)


class QueryDeadlineTests(unittest.TestCase):
    def run_deadline(self, *, generation=3, state=None, packet=None):
        probe = {
            "stopped": False, "boot": "current", "requestNumber": 3, "phase": "unknown",
            "epoch": "", "revision": -1, "accepted": 0, "boundEpoch": "",
            "boundOwner": "", "boundIdentity": "", "stops": 0,
        } | (state or {})
        script = "const probe=" + json.dumps(probe) + ";\n"
        script += (
            "probe.observations=[];"
            "probe.observe=packet=>probe.observations.push({phase:probe.phase,packet:packet});"
            "probe.sendQuery=()=>{throw new Error('deadline retried the query');};"
            "probe.freshQuery=()=>{throw new Error('deadline replaced the query');};"
            "probe.stopQueryDeadline=()=>{++probe.stops;};"
            "const methods=(function(){with(probe){return ["
        )
        script += qml_handler("queryTimedOut") + "," + qml_handler("acceptPacket")
        script += "];}})();\nmethods[0](" + json.dumps(generation) + ");\n"
        if packet is not None:
            # Acceptance is after identity verification; the native suite tests that boundary.
            script += "methods[1](" + json.dumps(packet) + ");\n"
        script += "process.stdout.write(JSON.stringify(probe));\n"
        result = subprocess.run(["node", "-"], input=script, capture_output=True, text=True,
                                timeout=10, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_deadline_is_unconfirmed_not_cancelled_or_retried(self):
        result = self.run_deadline()
        self.assertEqual(result["phase"], "unconfirmed")
        self.assertEqual(result["requestNumber"], 3)
        self.assertFalse(result["stopped"])
        self.assertEqual(result["observations"], [{"phase": "unconfirmed", "packet": None}])

    def test_old_deadline_cannot_affect_a_newer_query(self):
        result = self.run_deadline(generation=2)
        self.assertEqual(result["phase"], "unknown")
        self.assertEqual(result["observations"], [])

    def test_deadline_does_not_downgrade_confirmed_state(self):
        result = self.run_deadline(state={"phase": "online", "boundEpoch": "confirmed"})
        self.assertEqual(result["phase"], "online")
        self.assertEqual(result["observations"], [])

    def test_stopped_consumer_ignores_the_deadline(self):
        result = self.run_deadline(state={"stopped": True})
        self.assertEqual(result["phase"], "unknown")
        self.assertEqual(result["observations"], [])

    def test_current_verified_late_state_is_accepted_after_deadline(self):
        packet = ReplyOrderingTests.packet(7)
        result = self.run_deadline(packet=packet)
        self.assertEqual(result["phase"], "online")
        self.assertEqual(result["requestNumber"], 3)
        self.assertEqual(result["accepted"], 1)
        self.assertEqual(result["revision"], 7)
        self.assertEqual(result["stops"], 1)

    def test_old_verified_late_request_stays_rejected_after_deadline(self):
        result = self.run_deadline(packet=ReplyOrderingTests.packet(1000, request=2))
        self.assertEqual(result["phase"], "unconfirmed")
        self.assertEqual(result["requestNumber"], 3)
        self.assertEqual(result["accepted"], 0)
        self.assertEqual(result["stops"], 0)


class PublicationLifetimeTests(unittest.TestCase):
    def run_empty_read(self, destination: str):
        script = (
            "const probe={replyDelayMs:2000,pendingPublication:null,stops:0,destroys:0};"
            "probe.pendingPublication={destination:':1.10',rows:[{id:1}],"
            "stop:()=>++probe.stops,destroy:()=>++probe.destroys};"
            "probe.publish=()=>{throw new Error('empty read published state');};"
            "const publicationFactory={createObject:()=>{"
            "throw new Error('empty read created a publication timer');}};"
            "const methods=(function(){with(probe){return ["
        )
        script += (qml_handler("cancelPublication", "provider.qml") + ","
                   + qml_handler("queuePublication", "provider.qml"))
        script += "];}})();probe.cancelPublication=methods[0];methods[1]([], "
        script += json.dumps(destination) + ");"
        script += ("process.stdout.write(JSON.stringify({pending:probe.pendingPublication!==null,"
                   "stops:probe.stops,destroys:probe.destroys}));\n")
        result = subprocess.run(["node", "-"], input=script, capture_output=True, text=True,
                                timeout=10, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_empty_replacement_read_cancels_the_previous_shell_batch(self):
        result = self.run_empty_read(":1.20")
        self.assertEqual(result, {"pending": False, "stops": 1, "destroys": 1})

    def test_empty_same_shell_read_does_not_retarget_the_existing_batch(self):
        result = self.run_empty_read(":1.10")
        self.assertEqual(result, {"pending": True, "stops": 0, "destroys": 0})


class FocusObservationTests(unittest.TestCase):
    def run_node(self, script: str):
        result = subprocess.run(["node", "-"], input=script, capture_output=True, text=True,
                                timeout=10, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_panel_activation_preserves_the_last_eligible_object(self):
        script = (
            "const probe={lastEligibleWindow:null,lastApplication:'',focusProbe:true};"
            "probe.traceFocus=()=>{};console.info=()=>{};"
            "const Tiling={eligibleForMaster:window=>!!window&&window.eligible};"
        )
        script += qml_handler("onWindowActivated", "provider.qml")
        script += ("const app={eligible:true,resourceClass:'pf.focus.alpha',"
                   "internalId:'private-a'};"
                   "onWindowActivated(app);"
                   "onWindowActivated({eligible:false,resourceClass:'plasmashell'});"
                   "process.stdout.write(JSON.stringify(probe.lastEligibleWindow===app));")
        self.assertTrue(self.run_node(script))

    def test_window_identifiers_do_not_enter_the_client_packet(self):
        probe = {
            "epoch": "a" * 32, "revision": 0, "capable": True, "refusal": -1,
            "lastApplication": "private-window-id", "competingProviderRejected": True,
            "selfOwner": ":1.0", "identityName": "org.plasmafusion.LayoutProbe.p" + "a" * 32,
        }
        script = "const probe=" + json.dumps(probe) + ";"
        script += ("console.info=()=>{};const writer={arguments:[],call:()=>{}};"
                   "const publish=(function(){with(probe){return ")
        script += qml_handler("publish", "provider.qml") + ";}})();"
        script += ("publish('online',[{id:1,consumer:'current',request:1}],':1.10');"
                   "const text=writer.arguments[0];"
                   "const messages=JSON.parse(text.slice('var messages = '.length,"
                   "text.indexOf(';var written=0;')));"
                   "process.stdout.write(messages[0].packet);")
        self.assertNotIn("application", self.run_node(script))

    def test_keyboard_trace_records_the_query_it_initiates(self):
        source = Path(__file__).with_name("consumer.qml").read_text()
        handler = re.search(r"Keys.onPressed: event => (\{.*?\n            \})", source, re.S)[1]
        script = (
            "const records=[];console.info=(name,row)=>records.push(JSON.parse(row));"
            "const Qt={Key_Space:32,Key_Return:13,Key_Enter:14,Key_Escape:27};"
            "const Screen={name:'Virtual-0'};const focusQuery={activeFocus:true};"
            "const probe={boot:'current',requestNumber:7,freshQuery:()=>++probe.requestNumber};"
            "const event={key:32,isAutoRepeat:false,accepted:false};(event=>"
        ) + handler + ")(event);process.stdout.write(JSON.stringify(records[0]));"
        self.assertEqual(self.run_node(script)["request"], 8)

    def test_target_intents_are_explicit_and_capture_the_calling_control_output(self):
        script = """
const Screen={name:'Virtual-0'};
const probe={
    targetEnabled:true,queryIntent:'query',requestOutput:'',preparedToken:'old',requestNumber:1,
    freshQuery:()=>{probe.queryIntent='query';++probe.requestNumber;}
};
""" + qml_handler("requestTarget") + """
requestTarget('prepare');
const prepare={intent:probe.queryIntent,output:probe.requestOutput,token:probe.preparedToken};
probe.preparedToken='opaque-preparation';
Screen.name='Virtual-1';
requestTarget('validate');
process.stdout.write(JSON.stringify({
    prepare,validate:{intent:probe.queryIntent,output:probe.requestOutput,token:probe.preparedToken}
}));
"""
        self.assertEqual(self.run_node(script), {
            "prepare": {"intent": "prepare", "output": "Virtual-0", "token": ""},
            "validate": {"intent": "validate", "output": "Virtual-1", "token": "opaque-preparation"},
        })

    def test_target_context_is_frozen_before_later_state_updates(self):
        script = """
const Screen={name:'Virtual-0'};
const original={epoch:'provider-a',generation:7,desktopId:'a',activityId:'activity',
                outputName:'Virtual-0',consumerLease:'provider-a:1'};
const probe={targetEnabled:true,targetContext:original,requestContext:null,preparedToken:'',
             freshQuery:()=>{probe.queryIntent='query';}};
""" + qml_handler("requestTarget") + """
requestTarget('prepare');
original.generation=99;
probe.targetContext={...original,desktopId:'b'};
requestTarget('validate');
process.stdout.write(JSON.stringify(probe.requestContext));
"""
        self.assertEqual(self.run_node(script), {
            "epoch": "provider-a", "generation": 7, "desktopId": "a",
            "activityId": "activity", "outputName": "Virtual-0", "consumerLease": "provider-a:1",
        })

    def test_confirmed_handoff_context_is_separate_from_the_original_prepare_intent(self):
        script = """
const epoch='a'.repeat(32);
const context={epoch,generation:1,desktopId:'desktop-a',activityId:'activity-a',
               outputName:'Virtual-0',consumerLease:epoch+':1'};
const probe={
    stopped:false,requestNumber:2,boundEpoch:'',boundOwner:'',boundIdentity:'',revision:-1,
    accepted:0,phase:'unknown',epoch:'',targetEnabled:true,targetContext:null,preparedContext:null,
    preparedToken:'',requestContext:{...context,generation:0},
    stopQueryDeadline:()=>{},observe:()=>{}
};
const accept=(function(){with(probe){return """ + qml_handler("acceptPacket") + """;}})();
accept({
    request:2,epoch,revision:1,status:'online',capable:true,backendOwner:':1.0',identityName:'alias',
    targetContext:context,preparation:{intent:'prepare',ready:true,reason:'',token:'opaque'}
});
process.stdout.write(JSON.stringify({
    original:probe.requestContext.generation,accepted:probe.preparedContext,
    token:probe.preparedToken
}));
"""
        self.assertEqual(self.run_node(script), {
            "original": 0, "accepted": {
                "epoch": "a" * 32, "generation": 1, "desktopId": "desktop-a",
                "activityId": "activity-a", "outputName": "Virtual-0",
                "consumerLease": "a" * 32 + ":1",
            }, "token": "opaque",
        })

    def test_menu_opening_freezes_context_but_waits_for_its_own_input(self):
        script = """
const Screen={name:'Virtual-0'};
const original={epoch:'provider',generation:7,desktopId:'a',activityId:'activity',
                outputName:'Virtual-0',consumerLease:'provider:1'};
let sent=0;
const probe={
    targetEnabled:true,targetContext:original,pendingMenuContext:null,targetPreparationPending:false,
    focusPopupOpen:false,preparedToken:'',preparedContext:null,preparedReady:false,
    freshQuery:()=>{++sent;probe.queryIntent='query';}
};
""" + qml_handler("openTargetMenu") + qml_handler("requestTarget") + """
openTargetMenu();
const beforeInput=sent;
original.generation=99;
probe.targetContext={...original,desktopId:'b'};
requestTarget('prepare');
process.stdout.write(JSON.stringify({
    beforeInput,sent,pending:probe.targetPreparationPending,context:probe.requestContext
}));
"""
        self.assertEqual(self.run_node(script), {
            "beforeInput": 0, "sent": 1, "pending": False, "context": {
                "epoch": "provider", "generation": 7, "desktopId": "a",
                "activityId": "activity", "outputName": "Virtual-0",
                "consumerLease": "provider:1",
            },
        })

    def test_readiness_loss_retains_only_the_inert_last_confirmed_snapshot(self):
        script = """
const epoch='a'.repeat(32);
const context={epoch,generation:1,desktopId:'a',activityId:'activity',outputName:'Virtual-0',
               consumerLease:epoch+':1'};
const probe={
    stopped:false,requestNumber:2,boundEpoch:'',boundOwner:'',boundIdentity:'',revision:-1,
    accepted:0,phase:'unknown',epoch:'',targetEnabled:true,targetContext:null,preparedContext:null,
    preparedToken:'',preparedReady:false,stopQueryDeadline:()=>{},observe:()=>{}
};
const accept=(function(){with(probe){return """ + qml_handler("acceptPacket") + """;}})();
const packet={request:2,epoch,revision:1,status:'online',capable:true,
              backendOwner:':1.0',identityName:'alias',targetContext:context,
              preparation:{intent:'prepare',ready:true,reason:'',token:'opaque'}};
accept(packet);
accept({...packet,revision:2,targetContext:{...context,generation:2},
        preparation:{intent:'prepare',ready:false,reason:'stale-context',token:''}});
process.stdout.write(JSON.stringify({
    ready:probe.preparedReady,token:probe.preparedToken,
    captured:probe.preparedContext && probe.preparedContext.generation,
    current:probe.targetContext.generation
}));
"""
        self.assertEqual(self.run_node(script),
                         {"ready": False, "token": "opaque", "captured": 1, "current": 2})

    def run_focus_receipt(self, fault=None):
        source = Path(__file__).with_name("scenario-bridge.sh").read_text()
        section = source.split("    queried=false\n", 1)[1]
        checker = section.split("<<'PY'\n", 1)[1].split("\nPY\n", 1)[0]
        online = {"boot": "current", "phase": "online", "request": 2,
                  "packet": {"consumer": "current", "request": 2}}
        key = {"boot": "current", "key": 32, "activeFocus": True,
               "screen": "Virtual-0", "request": 3}
        outbound = {"boot": "current", "request": 3}
        accepted = {"boot": "current", "phase": "online", "request": 3,
                    "packet": {"consumer": "current", "request": 3}}
        wake = {"event": "wake", "rememberedClass": "pf.focus.alpha",
                "rememberedAlive": True, "rememberedOutput": "Virtual-0",
                "activeOutput": "Virtual-0", "desktopId": "desktop", "activityId": "activity"}
        events = [("observation", online), ("keyboard-query", key), ("query", outbound)]
        if fault == "wrong-outbound":
            outbound["request"] = 2
        if fault == "wrong-receiver":
            accepted["packet"]["consumer"] = "other"
        if fault == "confirmation-before-key":
            events.insert(0, ("observation", accepted))
        elif fault == "confirmation-before-outbound":
            events.insert(2, ("observation", accepted))
        elif fault != "pre-key-online-only":
            events.append(("observation", accepted))
        with tempfile.TemporaryDirectory(prefix="pf-focus-check-", dir="/tmp/opencode") as scratch:
            root = Path(scratch)
            shell = root / "shell.log"
            shell.write_text("".join(
                f"qml: layout-probe-{name} {json.dumps(row)}\n" for name, row in events
            ))
            native = root / "kwin.log"
            native.write_text("qml: layout-probe-focus " + json.dumps(wake) + "\n")
            # Keep the old independent snapshot so the RED case reproduces the mixed-read bug.
            observations = root / "observations.json"
            observations.write_text(json.dumps([{"consumer": "current", "observation": online}]))
            baseline = root / "baseline.json"
            baseline.write_text(json.dumps({
                "shellLines": 0, "kwinLines": 1 if fault == "pre-key-wake-only" else 0,
            }))
            return subprocess.run(
                [sys.executable, "-", str(shell), str(native), "current",
                 str(observations), str(baseline)], input=checker, capture_output=True,
                text=True, timeout=10, check=False,
            )

    def test_focus_receipt_follows_the_keys_actual_query_generation(self):
        result = self.run_focus_receipt()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_focus_receipt_rejects_a_pre_key_online_snapshot(self):
        result = self.run_focus_receipt("pre-key-online-only")
        self.assertNotEqual(result.returncode, 0, "old online state certified a new key query")

    def test_focus_receipt_requires_ordered_outbound_and_confirmation(self):
        for fault in ("wrong-outbound", "wrong-receiver", "confirmation-before-key",
                      "confirmation-before-outbound", "pre-key-wake-only"):
            with self.subTest(fault=fault):
                self.assertNotEqual(self.run_focus_receipt(fault).returncode, 0, fault)




class RetirementDeliveryTests(unittest.TestCase):
    def run_delivery(self, swapped: bool):
        scenario = Path(__file__).with_name("scenario-bridge.sh").read_text()
        section = scenario.split("retirement_received=false\n", 1)[1]
        checker = section.split("<<'PY'\n", 1)[1].split("\nPY\n", 1)[0]
        with tempfile.TemporaryDirectory(
            prefix="pf-layout-delivery-", dir="/tmp/opencode"
        ) as scratch:
            root = Path(scratch)
            before = [{"consumer": boot, "observation": {
                "epoch": "old", "revision": 4, "packet": {"request": 1},
            }} for boot in ("a", "b")]
            after = [{"consumer": boot, "observation": {
                "phase": "unknown", "packet": None, "epoch": "", "revision": -1, "request": 2,
            }} for boot in ("a", "b")]
            (root / "before.json").write_text(json.dumps(before))
            (root / "after.json").write_text(json.dumps(after))
            consumers = ("a", "b")
            receivers = tuple(reversed(consumers)) if swapped else consumers
            frames = [{"consumer": boot, "receiverBoot": receiver,
                       "status": "offline", "epoch": "old", "request": 1, "revision": 5}
                      for boot, receiver in zip(consumers, receivers)]
            (root / "trace.log").write_text("".join(
                "qml: layout-probe-received " + json.dumps(frame) + "\n" for frame in frames
            ))
            return subprocess.run(
                [sys.executable, "-", str(root / "before.json"), str(root / "after.json"),
                 str(root / "trace.log")], input=checker, text=True, capture_output=True,
                timeout=10, check=False,
            )

    def test_retirement_delivery_accepts_the_correct_live_receivers(self):
        result = self.run_delivery(swapped=False)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_retirement_delivery_rejects_swapped_live_receivers(self):
        result = self.run_delivery(swapped=True)
        self.assertNotEqual(result.returncode, 0,
                            "packet claims alone certified the wrong receivers")


if __name__ == "__main__":
    unittest.main()
