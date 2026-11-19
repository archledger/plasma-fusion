# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Process replacement with a target-mode seed: fresh contexts and leases after each restart, and a
serialized pipeline in each provider lifetime."""

import contextlib
import importlib.util
import io
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

HERE = Path(__file__).resolve().parent
LIFECYCLE = HERE / "lifecycle.py"
E1, E2, E3 = "a" * 32, "b" * 32, "d" * 32
BASE = ["private-bus", "shell-restart", "backend-restart"]


def runner():
    spec = importlib.util.spec_from_file_location("layout_lifecycle_target", LIFECYCLE)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def row(boot, epoch, lease, *, context_epoch=None, context=True, preparation=None,
        completion=None):
    """A receiver's latest online observation, as consumer.qml logs it in target mode."""
    target = {"epoch": context_epoch or epoch, "generation": 0, "desktopId": "desktop",
              "activityId": "activity", "outputName": "Virtual-1", "consumerLease": lease}
    packet = {"consumer": boot, "epoch": epoch, "revision": 3, "status": "online",
              "capable": True, "refusal": -1, "request": 1, "preparation": preparation,
              "completion": completion, "targetContext": target if context else None,
              "competingProviderRejected": True, "backendOwner": ":1.4",
              "identityName": "org.plasmafusion.LayoutProbe.p" + epoch}
    return {"boot": boot, "phase": "online", "epoch": epoch, "revision": 3, "accepted": 1,
            "packet": packet, "request": 1}


def shells():
    """Two shells under the first KWin, then one under its replacement."""
    return [[row("1:0.1", E1, E1 + ":1"), row("1:0.2", E1, E1 + ":2")],
            [row("2:0.1", E1, E1 + ":3"), row("2:0.2", E1, E1 + ":4")],
            [row("3:0.1", E2, E2 + ":1"), row("3:0.2", E2, E2 + ":2")]]


LEASES = [[E1 + ":1", E1 + ":2"], [E1 + ":3", E1 + ":4"], [E2 + ":1", E2 + ":2"]]
EPOCHS = [E1, E1, E2]
PIPELINE = ["qml: layout-probe: initialized true -1", "qml: layout-probe: wake received",
            "qml: layout-probe: read started", "qml: layout-probe: mailbox rows 2",
            "qml: layout-probe: publication online 2", "qml: layout-probe: read finished",
            "qml: layout-probe: publication writes 2", "qml: layout-probe: read started",
            "qml: layout-probe: read finished", "qml: layout-probe: publication offline 2"]


def appletsrc(leases):
    """A shell's saved widget configuration with a query request and a bound response per
    widget, one per lease."""
    return "".join(
        f"[Containments][2][Applets][{number}][Configuration][General]\n"
        + 'layoutRequest={"consumer":"1:0.' + str(number) + '","intent":"query",'
        + '"consumerLease":""}\n'
        + 'layoutResponse={"consumer":"1:0.' + str(number) + '","targetContext":{"epoch":"'
        + lease.split(":")[0] + '","consumerLease":"' + lease + '"}}\n\n'
        for number, lease in enumerate(leases, 1))


def receipt(**changes):
    value = {"schema": 1, "scope": "p0-process-replacement", "passed": True, "mode": "target",
             "busIds": ["c" * 32] * 3, "backendOwners": [":1.4", ":1.498"],
             "shellOwners": [":1.16", ":1.245", ":1.504"], "checks": BASE + ["target-bootstrap"],
             "leases": LEASES, "epochs": EPOCHS, "savedLeases": LEASES[0]}
    return value | changes


class LifecycleTargetTests(unittest.TestCase):
    def setUp(self):
        self.runner = runner()

    def test_the_seeds_target_flag_selects_target_mode(self):
        with tempfile.TemporaryDirectory(dir="/tmp/opencode") as scratch:
            home = Path(scratch)
            (home / ".config").mkdir()
            config = home / ".config/kwinrc"
            config.write_text("[Script-plasmafusion-layout-probe]\nProbeAuthorized=true\n"
                              "TargetProbe=true\n")
            self.assertEqual(self.runner.probe_mode(home), "target")
            config.write_text("[Script-plasmafusion-layout-probe]\nProbeAuthorized=true\n"
                              "TargetProbe=false\n")
            self.assertEqual(self.runner.probe_mode(home), "plain")

    def test_fresh_target_receivers_pass_and_record_their_leases(self):
        self.assertEqual(self.runner.target_bootstrap(shells()),
                         {"leases": LEASES, "epochs": EPOCHS})

    def test_a_receiver_without_a_context_of_its_lifetime_fails(self):
        for change in ({"context": False}, {"context_epoch": E2}):
            with self.subTest(change=change):
                groups = shells()
                groups[1][0] = row("2:0.1", E1, E1 + ":3", **change)
                with self.assertRaisesRegex(ValueError, "no context of its provider lifetime"):
                    self.runner.target_bootstrap(groups)

    def test_a_lease_of_another_lifetime_fails(self):
        groups = shells()
        groups[2][1] = row("3:0.2", E2, E1 + ":5")
        with self.assertRaisesRegex(ValueError, "lease is not one of its provider lifetime"):
            self.runner.target_bootstrap(groups)

    def test_a_lease_issued_twice_fails(self):
        # A provider that numbers leases per shell gives the restarted shell's receivers the
        # leases the previous shell's receivers had.
        groups = shells()
        groups[1] = [row("2:0.1", E1, E1 + ":1"), row("2:0.2", E1, E1 + ":2")]
        with self.assertRaisesRegex(ValueError, "same lease"):
            self.runner.target_bootstrap(groups)

    def test_the_restarted_shells_receivers_need_later_leases(self):
        groups = shells()
        groups[0] = [row("1:0.1", E1, E1 + ":5"), row("1:0.2", E1, E1 + ":6")]
        with self.assertRaisesRegex(ValueError, "no later leases"):
            self.runner.target_bootstrap(groups)

    def test_a_fresh_receiver_carries_no_preparation_or_completion(self):
        decided = {"request": 1, "intent": "prepare", "accepted": False, "token": "",
                   "reason": "busy"}
        for change in ({"completion": decided}, {"preparation": {"intent": "prepare"}}):
            with self.subTest(change=change):
                groups = shells()
                groups[2][0] = row("3:0.1", E2, E2 + ":1", **change)
                with self.assertRaisesRegex(ValueError, "preparation or completion"):
                    self.runner.target_bootstrap(groups)

    def test_a_shell_restart_keeps_the_epoch_and_a_kwin_restart_changes_it(self):
        same = shells()
        same[2] = [row("3:0.1", E1, E1 + ":5"), row("3:0.2", E1, E1 + ":6")]
        changed = shells()
        changed[1] = [row("2:0.1", E2, E2 + ":3"), row("2:0.2", E2, E2 + ":4")]
        # Three epochs: the shell restart changed it although the KWin restart did too.
        distinct = shells()
        distinct[1] = [row("2:0.1", E3, E3 + ":3"), row("2:0.2", E3, E3 + ":4")]
        for groups in (same, changed, distinct):
            with self.subTest(epochs=[group[0]["epoch"][0] for group in groups]):
                with self.assertRaisesRegex(ValueError, "epoch"):
                    self.runner.target_bootstrap(groups)

    def test_two_receivers_per_shell_are_required(self):
        for count in (1, 0):
            with self.subTest(receivers=count):
                groups = shells()
                groups[1] = groups[1][:count]
                with self.assertRaisesRegex(ValueError, "two receivers in each shell"):
                    self.runner.target_bootstrap(groups)

    def test_only_saved_responses_hold_the_retained_leases(self):
        # A saved target request always has the key, empty for a query; a lease counts only in a
        # saved response.
        request = ('layoutRequest={"consumer":"1:0.1","request":1,"intent":"query",'
                   '"consumerLease":""}')
        validate = 'layoutRequest={"intent":"validate","consumerLease":"' + E1 + ':1"}'
        unbound = 'layoutResponse={"consumer":"1:0.1","targetContext":null}'
        bound = ('layoutResponse={"consumer":"1:0.2","targetContext":{"epoch":"' + E1
                 + '","consumerLease":"' + E1 + ':2"}}')
        leases = self.runner.saved_response_leases
        self.assertEqual(leases("\n".join(["[General]", request, validate, unbound])), set())
        self.assertEqual(leases("\n".join([request, bound, "plugin=org.plasmafusion.layoutprobe"])),
                         {E1 + ":2"})

    def test_a_frame_without_an_epoch_fails_with_a_message(self):
        for index in (0, 1):
            with self.subTest(receiver=index):
                groups = shells()
                del groups[1][index]["packet"]["epoch"]
                with self.assertRaisesRegex(ValueError, "no context of its provider lifetime"):
                    self.runner.target_bootstrap(groups)

    def test_a_malformed_receiver_row_fails_with_a_message(self):
        groups = shells()
        groups[0] = [groups[0][0], {"boot": "1:0.2", "packet": None}]
        with self.assertRaisesRegex(ValueError, "malformed receiver row"):
            self.runner.target_bootstrap(groups)

    def test_target_mode_waits_for_a_leased_context(self):
        rows = shells()[0]
        unleased = [rows[0], row("1:0.2", E1, E1 + ":2", context=False)]
        self.assertTrue(self.runner.bootstrapped(rows, "target"))
        self.assertFalse(self.runner.bootstrapped(unleased, "target"))
        self.assertTrue(self.runner.bootstrapped(unleased, "plain"))
        self.assertFalse(self.runner.bootstrapped([], "plain"))

    def test_a_target_receipt_requires_its_check_and_consistent_leases(self):
        self.runner.check_receipt(receipt())
        with self.assertRaisesRegex(ValueError, "replacement receipt"):
            self.runner.check_receipt(receipt(checks=BASE))
        with self.assertRaisesRegex(ValueError, "same lease"):
            self.runner.check_receipt(receipt(leases=[LEASES[0], LEASES[0], LEASES[2]]))
        with self.assertRaisesRegex(ValueError, "replacement receipt"):
            self.runner.check_receipt(receipt(mode="other"))
        unknown = receipt(mode="other", checks=BASE)
        del unknown["leases"], unknown["epochs"], unknown["savedLeases"]
        with self.assertRaisesRegex(ValueError, "replacement receipt"):
            self.runner.check_receipt(unknown)
        with self.assertRaisesRegex(ValueError, "for each of three shells"):
            self.runner.check_receipt(receipt(leases=LEASES[:2]))
        # Missing, incomplete or other leases, and entries that are not leases at all.
        for saved in (None, LEASES[0][:1], [E1 + ":7"], [LEASES[0]], LEASES[0] + [None],
                      LEASES[0] + ["lease"]):
            with self.subTest(saved=saved):
                with self.assertRaisesRegex(ValueError, "saved responses do not hold"):
                    self.runner.check_receipt(receipt(savedLeases=saved))

    def test_a_plain_receipt_may_name_its_mode(self):
        value = receipt(mode="plain", checks=BASE)
        del value["leases"], value["epochs"], value["savedLeases"]
        self.runner.check_receipt(value)
        with self.assertRaisesRegex(ValueError, "replacement receipt"):
            self.runner.check_receipt(value | {"checks": BASE + ["target-bootstrap"]})


class LifecycleTargetResultTests(unittest.TestCase):
    """The host-side check recomputes a target run from its raw logs."""

    def setUp(self):
        scratch = tempfile.TemporaryDirectory(prefix="pf-lifecycle-target-", dir="/tmp/opencode")
        self.addCleanup(scratch.cleanup)
        self.output = Path(scratch.name)
        self.runner = runner()
        self.groups = shells()
        for number, rows in enumerate(self.groups, 1):
            unknown = [{"boot": item["boot"], "phase": "unknown", "epoch": "", "revision": -1,
                        "accepted": 0, "packet": None, "request": 1} for item in rows]
            (self.output / f"shell-{number}.log").write_text("".join(
                "qml: layout-probe-observation " + json.dumps(item) + "\n"
                for item in unknown + rows))
            (self.output / f"shell-{number}-observations.json").write_text(json.dumps(rows))
        for number in (1, 2):
            (self.output / f"kwin-{number}.log").write_text("\n".join(PIPELINE) + "\n")
        (self.output / "shell-1-appletsrc").write_text(appletsrc(LEASES[0]))
        (self.output / "lifecycle-result.json").write_text(json.dumps(receipt()))

    def check(self):
        return self.runner.check_run(self.output)

    def test_a_complete_target_run_passes(self):
        self.assertEqual(self.check()["mode"], "target")

    def test_the_recheck_leaves_the_search_path_as_it_found_it(self):
        path = [entry for entry in sys.path if entry != str(HERE)]
        with mock.patch.object(sys, "path", list(path)):
            self.check()
            self.assertEqual(sys.path, path)

    def test_the_saved_leases_are_recomputed_from_the_kept_configuration(self):
        # The run keeps the configuration the second shell starts from; the receipt's saved
        # leases must be exactly its responses' leases.
        kept = self.output / "shell-1-appletsrc"
        for case, leases in {"another lease": [E1 + ":1", E1 + ":7"],
                             "one more": LEASES[0] + [E1 + ":3"], "none": []}.items():
            with self.subTest(case=case):
                kept.write_text(appletsrc(leases))
                with self.assertRaisesRegex(ValueError, "kept configuration"):
                    self.check()
        kept.unlink()
        with self.assertRaisesRegex(OSError, "shell-1-appletsrc"):
            self.check()

    def test_a_recorded_receiver_must_be_in_its_shells_log(self):
        rows = self.groups[1]
        rows[0]["revision"] = 9
        (self.output / "shell-2-observations.json").write_text(json.dumps(rows))
        with self.assertRaisesRegex(ValueError, "shell-2.log"):
            self.check()

    def test_the_receipt_must_match_the_receivers_frames(self):
        changed = receipt(leases=[LEASES[0], [E1 + ":3", E1 + ":7"], LEASES[2]])
        (self.output / "lifecycle-result.json").write_text(json.dumps(changed))
        with self.assertRaisesRegex(ValueError, "do not match"):
            self.check()

    def test_each_provider_lifetime_must_keep_reads_and_publications_serialized(self):
        lines = list(PIPELINE)
        # A read starts while the publication is outstanding.
        lines.insert(lines.index("qml: layout-probe: publication writes 2"),
                     "qml: layout-probe: read started")
        (self.output / "kwin-2.log").write_text("\n".join(lines) + "\n")
        with self.assertRaisesRegex(ValueError, "kwin-2.log: a read started"):
            self.check()

    def test_the_teardown_after_the_offline_frame_is_not_replayed(self):
        # Stopping sends the offline frame even while a publication is outstanding; nothing from
        # the offline frame on counts.
        lines = PIPELINE[:-1] + ["qml: layout-probe: read started",
                                 "qml: layout-probe: publication online 2",
                                 "qml: layout-probe: publication offline 2",
                                 "qml: layout-probe: publication online 2"]
        (self.output / "kwin-1.log").write_text("\n".join(lines) + "\n")
        self.check()

    def test_a_provider_lifetime_without_a_read_and_a_publication_fails(self):
        start = "qml: layout-probe: initialized true -1\n"
        cases = {"neither": "", "read only": "qml: layout-probe: read started\n"
                 "qml: layout-probe: read finished\n",
                 "publication only": "qml: layout-probe: publication online 2\n"
                 "qml: layout-probe: publication writes 2\n"}
        for case, middle in cases.items():
            with self.subTest(case=case):
                (self.output / "kwin-1.log").write_text(
                    start + middle + "qml: layout-probe: publication offline 2\n")
                with self.assertRaisesRegex(ValueError, "kwin-1.log: no read and publication"):
                    self.check()

    def test_a_plain_run_is_checked_by_its_receipt_alone(self):
        value = receipt(mode="plain", checks=BASE)
        del value["leases"], value["epochs"], value["savedLeases"]
        (self.output / "lifecycle-result.json").write_text(json.dumps(value))
        (self.output / "kwin-1.log").unlink()
        self.assertEqual(self.check()["mode"], "plain")

    def test_check_result_cli_reports_and_refuses(self):
        command = [sys.executable, str(LIFECYCLE), "--check-result", str(self.output)]
        passed = subprocess.run(command, capture_output=True, text=True, timeout=30,
                                check=False)
        self.assertEqual(passed.returncode, 0, passed.stderr)
        self.assertIn("PASS", passed.stdout)
        combined = subprocess.run(command + ["--name", "layout-control-lc-unit"],
                                  capture_output=True, text=True, timeout=30, check=False)
        self.assertNotEqual(combined.returncode, 0)
        self.assertIn("no other arguments", combined.stderr)
        (self.output / "lifecycle-result.json").unlink()
        missing = subprocess.run(command, capture_output=True, text=True, timeout=30,
                                 check=False)
        self.assertNotEqual(missing.returncode, 0)
        self.assertIn("lifecycle-result.json", missing.stderr)

    def run_container(self, skip=()):
        root = Path(tempfile.mkdtemp(dir=self.output))
        output = root / "vsession-out/layout-control-lc-unit"

        def container(command, **_):
            # The container writes the run's evidence: here a copy of a complete target run.
            for path in self.output.iterdir():
                if path.is_file() and path.name not in skip:
                    (output / path.name).write_bytes(path.read_bytes())
            return subprocess.CompletedProcess(command, 0)

        with (mock.patch.object(self.runner.subprocess, "run", side_effect=container),
              contextlib.redirect_stdout(io.StringIO()) as printed):
            self.runner.run_container(root / "build/seed", output, "layout-control-lc-unit",
                                      "1" * 64)
        return printed.getvalue()

    def test_the_runner_checks_the_run_after_its_container(self):
        self.assertIn("PASS", self.run_container())
        with self.assertRaisesRegex(OSError, "kwin-1.log"):
            self.run_container(skip={"kwin-1.log"})


if __name__ == "__main__":
    unittest.main()
