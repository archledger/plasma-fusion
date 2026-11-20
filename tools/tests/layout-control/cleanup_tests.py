# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Separate functional receipts from owned-process cleanup qualification."""

import copy
import hashlib
import importlib
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

PREPARER = Path(__file__).with_name("prepare_seed.py")


def write_cleanup_fixture(directory: Path) -> dict:
    private = "/var/tmp/pfv-layout-control-unit"
    controller = {
        "pid": 5, "parent": 3, "start": 50, "uid": 1000, "executable": "/usr/bin/bash",
        "home": private + "/home", "runtime": private + "/run",
    }
    shell = {
        "pid": 7, "parent": 5, "start": 100, "uid": 1000,
        "executable": "/usr/bin/plasmashell", "home": private + "/home", "runtime": private + "/run",
    }
    before = {"bus": "a" * 32, "backend": ":1.0", "shell": ":1.20"}
    after = {**before, "shell": ""}
    records = {
        "cleanup-identity.json": {
            "schema": 1, "root": private, "controller": controller, "shell": shell, "session": before,
        },
        "cleanup-request.json": {
            "schema": 1, "signal": "SIGTERM", "shell": shell, "session": before,
        },
        "cleanup-stopped.json": {
            "schema": 1, "signal": "SIGTERM", "shell": shell,
            "exitObserved": True, "session": after,
        },
        "cleanup-result.json": {
            "schema": 1, "passed": True, "signal": "SIGTERM", "exit": 0,
            "shell": shell, "before": before, "after": after,
        },
    }
    for name, value in records.items():
        (directory / name).write_text(json.dumps(value))
    for name in ("kwin.log", "plasmashell.log"):
        (directory / name).write_text("")
    (directory / "container.log").write_text("session rc=0\n")
    (directory / "teardown.log").write_text("123.0 done; left: none\n")
    return records


class CleanupGateTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix="pf-cleanup-gate-")
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)
        (self.root / "scenario.log").write_text("scenario rc=0\nsession rc=0\n")
        (self.root / "layout-probe-result.json").write_text(json.dumps({
            "schema": 1, "passed": True, "checks": ["roundtrip-native", "retirement"],
        }))
        write_cleanup_fixture(self.root)

    def run_check(self):
        return subprocess.run(
            [sys.executable, str(PREPARER), "--check-result", str(self.root)],
            capture_output=True, text=True, timeout=10, check=False,
        )

    def test_complete_owned_cleanup_can_qualify_a_functional_receipt(self):
        result = self.run_check()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_functional_zero_cannot_hide_native_crash_diagnostics(self):
        for filename, diagnostic in (
            ("kwin.log", "inner.sh: line 1: 7 Aborted (core dumped) plasmashell\n"),
            ("plasmashell.log", 'dbus[7]: assertion "pending != NULL" failed in file dbus.c\n'),
            ("plasmashell.log", "KCrash: Application 'plasmashell' crashing...\n"),
            ("container.log", "Segmentation fault (core dumped)\n"),
            ("kwin.log", "received SIGABRT\n"),
        ):
            with self.subTest(filename=filename, diagnostic=diagnostic):
                write_cleanup_fixture(self.root)
                (self.root / filename).write_text(diagnostic)
                result = self.run_check()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("crash", result.stderr.lower())

    def test_missing_or_partial_cleanup_evidence_is_not_success(self):
        for filename in (
            "cleanup-identity.json", "cleanup-request.json", "cleanup-stopped.json", "cleanup-result.json",
            "kwin.log", "plasmashell.log", "container.log", "teardown.log",
        ):
            with self.subTest(filename=filename):
                write_cleanup_fixture(self.root)
                (self.root / filename).unlink()
                result = self.run_check()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("cleanup", result.stderr.lower())
        write_cleanup_fixture(self.root)
        (self.root / "cleanup-result.json").write_text('{"schema":1')
        self.assertNotEqual(self.run_check().returncode, 0)

    def test_abnormal_status_or_contradictory_identity_cannot_qualify(self):
        for record, field, value in (
            ("cleanup-result.json", "exit", 134),
            ("cleanup-result.json", "exit", False),
            ("cleanup-result.json", "passed", False),
            ("cleanup-result.json", "schema", True),
            ("cleanup-result.json", "signal", "SIGKILL"),
            ("cleanup-stopped.json", "exitObserved", False),
            ("cleanup-request.json", "shell", {"pid": 99}),
            ("cleanup-request.json", "signal", "SIGKILL"),
            ("cleanup-stopped.json", "shell", {"pid": 99}),
            ("cleanup-result.json", "shell", {"pid": 99}),
            ("cleanup-result.json", "after", {"bus": "b" * 32, "backend": ":1.0", "shell": ""}),
            ("cleanup-result.json", "after", {"bus": "a" * 32, "backend": ":1.99", "shell": ""}),
            ("cleanup-result.json", "after", {"bus": "a" * 32, "backend": ":1.0", "shell": ":1.30"}),
        ):
            with self.subTest(record=record, field=field, value=value):
                records = write_cleanup_fixture(self.root)
                changed = copy.deepcopy(records[record])
                changed[field] = value
                (self.root / record).write_text(json.dumps(changed))
                self.assertNotEqual(self.run_check().returncode, 0)

    def test_residual_forced_or_incomplete_sweep_cannot_qualify(self):
        for diagnostic in (
            "123.0 done; left: 7\n",
            "123.0 round 1 SIGKILL 7\n124.0 done; left: none\n",
            "123.0 round 1 SIGTERM 7:plasmashell\n",
        ):
            with self.subTest(diagnostic=diagnostic):
                write_cleanup_fixture(self.root)
                (self.root / "teardown.log").write_text(diagnostic)
                self.assertNotEqual(self.run_check().returncode, 0)

    def test_every_copied_process_identity_is_typed_not_just_value_equal(self):
        for name, field, value in (
            ("cleanup-request.json", "pid", 7.0),
            ("cleanup-stopped.json", "start", 100.0),
            ("cleanup-result.json", "uid", 1000.0),
        ):
            with self.subTest(name=name, field=field):
                records = write_cleanup_fixture(self.root)
                changed = copy.deepcopy(records[name])
                changed["shell"][field] = value
                (self.root / name).write_text(json.dumps(changed))
                self.assertNotEqual(self.run_check().returncode, 0)

    def test_nonfatal_warnings_and_bounded_wait_assertions_are_not_crashes(self):
        (self.root / "plasmashell.log").write_text(
            "kf.solid: Not connected to D-Bus server\nkpipewire_logging: Failed to connect to PipeWire\n"
        )
        (self.root / "target-reply-wait.log").write_text(
            "Traceback (most recent call last):\nAssertionError\n"
        )
        result = self.run_check()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_failed_missing_or_duplicate_outer_status_cannot_qualify(self):
        for text in ("session rc=1\n", "", "session rc=0\nsession rc=0\n"):
            with self.subTest(text=text):
                write_cleanup_fixture(self.root)
                (self.root / "container.log").write_text(text)
                self.assertNotEqual(self.run_check().returncode, 0)


class CleanupOwnershipTests(unittest.TestCase):
    def setUp(self):
        self.module = importlib.import_module(
            f"{__package__}.cleanup" if __package__ else "cleanup"
        )
        self.scratch = tempfile.TemporaryDirectory(prefix="pf-cleanup-owner-")
        self.addCleanup(self.scratch.cleanup)
        self.records = write_cleanup_fixture(Path(self.scratch.name))
        self.identity = self.records["cleanup-identity.json"]
        self.root = Path(self.identity["root"])
        self.shell = self.identity["shell"]

    def patch(self, name, **kwargs):
        patcher = mock.patch.object(self.module, name, **kwargs)
        value = patcher.start()
        self.addCleanup(patcher.stop)
        return value

    def prepare_signal(self):
        self.patch("private_root", return_value=self.root)
        self.patch("read_record", side_effect=lambda root, name: copy.deepcopy(self.records[name]))
        self.process = self.patch("read_process", return_value=copy.deepcopy(self.shell))
        self.controller = self.patch("_controller_is_current", return_value=True)
        self.session = self.patch("session_snapshot", return_value=self.identity["session"])
        self.query = self.patch("qdbus", return_value=str(self.shell["pid"]))
        self.patch("_withdrawn_session", return_value=self.records["cleanup-result.json"]["after"])
        self.written = self.patch("write_record")
        for parent, name, kwargs in (
            (self.module.os, "geteuid", {"return_value": 1000}),
            (self.module.os, "pidfd_open", {"return_value": 11}),
            (self.module.os, "close", {}),
            (self.module.os, "kill", {"side_effect": AssertionError("by-PID signalling forbidden")}),
            (self.module.os, "killpg", {"side_effect": AssertionError("group signalling forbidden")}),
            (self.module.signal, "pidfd_send_signal", {}),
        ):
            patcher = mock.patch.object(parent, name, **kwargs)
            value = patcher.start()
            self.addCleanup(patcher.stop)
            if name == "pidfd_open":
                self.opened = value
            elif name == "close":
                self.closed = value
            elif name == "pidfd_send_signal":
                self.signalled = value
        self.poller = mock.Mock()
        self.poller.poll.side_effect = [[], [(11, self.module.select.POLLIN)]]
        patcher = mock.patch.object(self.module.select, "poll", return_value=self.poller)
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_process_validation_requires_exact_owned_shell_and_controller(self):
        self.module.validate_shell(self.shell, self.identity["controller"], self.root, 1000)
        for field, value in (
            ("pid", True), ("pid", 1), ("pid", 2 ** 40), ("parent", 99), ("uid", 0),
            ("start", 0), ("executable", "/usr/bin/python3"),
            ("home", "/home/test"), ("runtime", "/run/user/1000"),
        ):
            with self.subTest(field=field, value=value):
                changed = {**self.shell, field: value}
                with self.assertRaises(ValueError):
                    self.module.validate_shell(changed, self.identity["controller"], self.root, 1000)

    def test_private_context_rejects_root_foreign_home_or_symlinked_output(self):
        environment = {
            "PFV": str(self.root), "HOME": str(self.root / "home"),
            "XDG_RUNTIME_DIR": str(self.root / "run"),
        }
        with mock.patch.object(self.module, "require_container"), \
                mock.patch.dict(os.environ, environment), \
                mock.patch.object(self.module.os, "geteuid", return_value=1000) as uid, \
                mock.patch.object(Path, "is_dir", return_value=True), \
                mock.patch.object(Path, "is_symlink", autospec=True, return_value=False) as symlink, \
                mock.patch.object(Path, "resolve", lambda path: path), \
                mock.patch.object(Path, "stat", return_value=SimpleNamespace(st_uid=1000)):
            self.assertEqual(self.module.private_root(), self.root)
            uid.return_value = 0
            with self.assertRaises(ValueError):
                self.module.private_root()
            uid.return_value = 1000
            with mock.patch.dict(os.environ, {"HOME": "/home/test"}):
                with self.assertRaises(ValueError):
                    self.module.private_root()
            symlink.side_effect = lambda path: path == self.root / "out"
            with self.assertRaises(ValueError):
                self.module.private_root()

    def test_capture_binds_unique_owner_to_direct_child_and_refuses_a_changed_session(self):
        self.patch("private_root", return_value=self.root)
        session = self.patch("session_snapshot", return_value=self.identity["session"])
        query = self.patch("qdbus", return_value=str(self.shell["pid"]))
        processes = self.patch("read_process")
        processes.side_effect = [self.identity["controller"], self.shell]
        written = self.patch("write_record")
        with mock.patch.object(self.module.os, "getppid", return_value=5), \
                mock.patch.object(self.module.os, "geteuid", return_value=1000), \
                mock.patch.object(Path, "exists", return_value=False) as exists:
            self.module.capture()
            self.assertEqual(written.call_args.args[2], self.identity)
            self.assertEqual(query.call_args.args[-1], self.identity["session"]["shell"])
            written.reset_mock()
            processes.side_effect = [self.identity["controller"], self.shell]
            session.side_effect = [
                self.identity["session"], {**self.identity["session"], "shell": ":1.99"},
            ]
            with self.assertRaises(ValueError):
                self.module.capture()
            written.assert_not_called()
            exists.return_value = True
            query.reset_mock()
            with self.assertRaises(ValueError):
                self.module.capture()
            query.assert_not_called()
            written.assert_not_called()

    def test_signal_uses_one_bound_descriptor_then_records_observed_exit(self):
        self.prepare_signal()
        self.assertEqual(self.module.signal_owned(), self.shell["pid"])
        self.opened.assert_called_once_with(self.shell["pid"], 0)
        self.signalled.assert_called_once_with(11, self.module.signal.SIGTERM, None, 0)
        self.closed.assert_called_once_with(11)
        record = self.written.call_args.args[2]
        self.assertIs(record["exitObserved"], True)
        self.assertEqual(record["shell"], self.shell)

    def test_pid_reuse_after_descriptor_open_refuses_without_signalling(self):
        self.prepare_signal()
        self.process.side_effect = [copy.deepcopy(self.shell), {**self.shell, "start": 101}]
        with self.assertRaises(ValueError):
            self.module.signal_owned()
        self.signalled.assert_not_called()
        self.closed.assert_called_once_with(11)
        self.written.assert_not_called()

    def test_foreign_controller_or_changed_lifetime_is_not_retargeted(self):
        self.prepare_signal()
        self.controller.return_value = False
        with self.assertRaises(ValueError):
            self.module.signal_owned()
        self.opened.assert_not_called()
        self.signalled.assert_not_called()
        self.controller.return_value = True
        self.session.return_value = {**self.identity["session"], "shell": ":1.99"}
        with self.assertRaises(ValueError):
            self.module.signal_owned()
        self.opened.assert_not_called()
        self.signalled.assert_not_called()

    def test_recorded_process_must_still_be_the_unique_shell_owners_pid(self):
        self.prepare_signal()
        self.query.return_value = "99"
        with self.assertRaises(ValueError):
            self.module.signal_owned()
        self.opened.assert_not_called()
        self.signalled.assert_not_called()

    def test_stop_timeout_never_retries_escalates_or_confirms_success(self):
        self.prepare_signal()
        self.poller.poll.side_effect = [[], []]
        with self.assertRaises(ValueError):
            self.module.signal_owned()
        self.signalled.assert_called_once_with(11, self.module.signal.SIGTERM, None, 0)
        self.closed.assert_called_once_with(11)
        names = [call.args[1] for call in self.written.call_args_list]
        self.assertEqual(names, ["cleanup-request.json"])

    def test_already_exited_target_is_not_a_successful_cleanup_request(self):
        self.prepare_signal()
        self.poller.poll.side_effect = [[(11, self.module.select.POLLIN)]]
        with self.assertRaises(ValueError):
            self.module.signal_owned()
        self.signalled.assert_not_called()
        self.written.assert_not_called()

    def test_duplicate_request_claim_prevents_a_second_signal_even_before_owner_loss(self):
        self.prepare_signal()
        claimed = {}

        def exclusive_record(root, name, value):
            if name in claimed:
                raise FileExistsError(name)
            claimed[name] = copy.deepcopy(value)

        self.written.side_effect = exclusive_record
        self.poller.poll.side_effect = [
            [], [(11, self.module.select.POLLIN)], [], [(11, self.module.select.POLLIN)],
        ]
        self.module.signal_owned()
        with self.assertRaises(FileExistsError):
            self.module.signal_owned()
        self.signalled.assert_called_once_with(11, self.module.signal.SIGTERM, None, 0)
        self.assertEqual(claimed["cleanup-request.json"]["shell"], self.shell)

    def test_confirmation_preserves_a_failed_parent_wait_instead_of_claiming_success(self):
        self.prepare_signal()
        with self.assertRaises(ValueError):
            self.module.confirm(134)
        record = self.written.call_args.args[2]
        self.assertIs(record["passed"], False)
        self.assertEqual(record["exit"], 134)
        self.signalled.assert_not_called()
        with self.assertRaises(ValueError):
            self.module.confirm(False)

    def test_confirmation_rejects_a_value_equal_but_malformed_process_copy(self):
        self.prepare_signal()
        changed = copy.deepcopy(self.records["cleanup-stopped.json"])
        changed["shell"]["pid"] = 7.0
        self.records["cleanup-stopped.json"] = changed
        with self.assertRaises(ValueError):
            self.module.confirm(0)
        self.written.assert_not_called()
        self.signalled.assert_not_called()

    def test_withdrawal_rejects_changed_bus_backend_or_replacement_shell(self):
        withdrawal = self.module._withdrawn_session
        self.prepare_signal()
        after = self.records["cleanup-result.json"]["after"]
        for field, value in (("bus", "b" * 32), ("backend", ":1.99"), ("shell", ":1.30")):
            with self.subTest(field=field):
                self.session.return_value = {**after, field: value}
                with self.assertRaises(ValueError):
                    withdrawal(self.identity["session"])
        self.signalled.assert_not_called()

    def test_record_writer_cannot_replace_a_prior_capture(self):
        root = Path(self.scratch.name) / "private"
        (root / "out").mkdir(parents=True)
        self.module.write_record(root, "cleanup-identity.json", {"original": True})
        with self.assertRaises(FileExistsError):
            self.module.write_record(root, "cleanup-identity.json", {"replacement": True})
        self.assertEqual(json.loads((root / "out/cleanup-identity.json").read_text()),
                         {"original": True})

    def test_cli_refuses_actions_outside_its_private_container(self):
        result = subprocess.run(
            [sys.executable, str(Path(__file__).with_name("cleanup.py")), "capture"],
            env={**os.environ, "PF_LAYOUT_PRIVATE_CONTAINER": "0"},
            capture_output=True, text=True, timeout=10, check=False,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("container", result.stderr.lower())


class CleanupSeedTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix="pf-cleanup-seed-")
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)
        self.stage = self.root / "build/stage"
        rules = self.stage / ".local/share/kwin/scripts/plasmafusion-placement/contents/ui/Tiling.js"
        rules.parent.mkdir(parents=True)
        rules.write_text("// staged rules\n")

    def check_seed(self, target):
        output = self.root / ("build/target" if target else "build/normal")
        result = subprocess.run(
            [sys.executable, str(PREPARER), "--stage", str(self.stage), "--output", str(output),
             *(["--target-probe"] if target else [])],
            cwd=self.root, capture_output=True, text=True, timeout=10, check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        inputs = json.loads((output / "probe-inputs.json").read_text())
        for name in ("cleanup.py", "lifecycle.py", *(["receipts.py"] if target else [])):
            helper = output / ".local/lib/layout-control" / name
            self.assertTrue(helper.is_file(), name)
            self.assertEqual(helper.read_bytes(), (PREPARER.parent / name).read_bytes())
            self.assertEqual(inputs[name], hashlib.sha256(helper.read_bytes()).hexdigest())
        configuration = output / ".config/pfv-env"
        self.assertIn("PF_LAYOUT_PRIVATE_CONTAINER=1\n", configuration.read_text())
        self.assertEqual(inputs["pfv-env"], hashlib.sha256(configuration.read_bytes()).hexdigest())
        return output, inputs

    def test_normal_seed_hashes_cleanup_helpers_but_omits_target_receipts(self):
        output, inputs = self.check_seed(False)
        self.assertFalse((output / ".local/lib/layout-control/receipts.py").exists())
        self.assertNotIn("receipts.py", inputs)

    def test_target_seed_hashes_cleanup_and_receipt_helpers(self):
        self.check_seed(True)


if __name__ == "__main__":
    unittest.main()
