#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""P0 safety/receipt checks; event-handler tests also require the repository's Node.js tool."""

import hashlib
import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

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

    def test_owner_lookup_uses_one_authoritative_query(self):
        with mock.patch.object(self.runner, "qdbus", return_value=":1.42") as query:
            self.assertEqual(self.runner.owner_of("org.kde.KWin"), ":1.42")
            query.assert_called_once_with("org.freedesktop.DBus", "/org/freedesktop/DBus",
                                          "org.freedesktop.DBus.GetNameOwner", "org.kde.KWin")


class OwnerEventTests(unittest.TestCase):
    def run_event(self, *, checking=None, bound=True, wrapped=False, service=None):
        source = Path(__file__).with_name("consumer.qml").read_text()
        start = source.index("function dbusNameOwnerChanged(")
        opening = source.index("{", start)
        depth = 1
        end = opening + 1
        while depth:
            depth += (source[end] == "{") - (source[end] == "}")
            end += 1
        handler = source[start:end]
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
