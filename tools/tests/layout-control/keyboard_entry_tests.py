# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Keyboard entry after panel focus: the remembered app, or a safe refusal, never the panel."""

import hashlib
import importlib
import json
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

if __package__:
    from .cleanup_tests import write_cleanup_fixture
else:
    from cleanup_tests import write_cleanup_fixture

HERE = Path(__file__).resolve().parent
PREPARER = HERE / "prepare_seed.py"
APP = "pf.focus.alpha"
BOOT = "current"
SHELL_PID = 202


def checker():
    """Import lazily: a missing checker fails these cases, not the whole entry point."""
    name = f"{__package__}.keyboard_entry" if __package__ else "keyboard_entry"
    return importlib.import_module(name)


def focus(*, cls="", pid=0, dock=False, desktop=False, popup=False, normal=False, remembered="",
          event="activation"):
    """A provider focus row, as traceFocus logs it."""
    return {"event": event, "activeClass": cls, "activeEligible": normal, "activePid": pid,
            "activeDock": dock, "activeDesktop": desktop, "activeAppletPopup": popup,
            "activeNormal": normal, "contextGeneration": 1, "rememberedClass": remembered,
            "rememberedAlive": bool(remembered), "rememberedCenter": None, "desktopId": "d",
            "activityId": "a", "activeOutput": "Virtual-0",
            "rememberedOutput": "Virtual-0" if remembered else ""}


def app_active():
    return focus(cls=APP, pid=101, normal=True, remembered=APP)


def dock(remembered, pid=SHELL_PID):
    return focus(cls="plasmashell", pid=pid, dock=True, remembered=remembered)


def popup(remembered):
    return focus(cls="org.kde.plasmashell", pid=SHELL_PID, popup=True, remembered=remembered)


def desktop_active():
    return focus(cls="plasmashell", pid=SHELL_PID, desktop=True)


# By default a verdict carries the completion it decides itself.
OWN = object()


def completion(request, accepted):
    """The answer the provider decides at a preparation's first handling."""
    return {"request": request, "intent": "prepare", "accepted": accepted,
            "token": "t" if accepted else "", "reason": "" if accepted else "stale-context"}


def verdict(request, ready, target, *, decision=OWN, reason=None):
    """A provider verdict row. A re-check passes the decision it keeps; an early return, None."""
    return {"consumer": BOOT, "request": request, "intent": "prepare", "revision": 5,
            "ready": ready, "reason": reason or ("" if ready else "stale-context"),
            "targetClass": target, "targetAlive": ready,
            "completion": completion(request, ready) if decision is OWN else decision}


def key(request):
    return {"boot": BOOT, "key": 32, "activeFocus": True, "screen": "Virtual-0",
            "request": request, "intent": "prepare"}


def accepted(request, ready, *, decision=OWN, reason=None):
    """A frame the consumer accepted: the re-checked preparation and the decided completion."""
    preparation = {"intent": "prepare", "ready": ready,
                   "reason": reason or ("" if ready else "stale-context"),
                   "token": "t" if ready else ""}
    return {"boot": BOOT, "phase": "online", "epoch": "e", "revision": 6, "accepted": 3,
            "packet": {"consumer": BOOT, "request": request, "preparation": preparation,
                       "completion": completion(request, ready) if decision is OWN else decision},
            "request": request}


def steps(**changes):
    """Each step's provider rows and shell rows, in the order the native runs log them (k03-5).
    Every scan re-checks the consumer's saved request, keeping its decided completion: request 2
    once Esc has returned focus to the app, and again around the refusal step's popup, until the
    key in that popup sends request 3; that one is re-checked as refused once Esc has focused the
    desktop. A change replaces one step's list."""
    ready, refused = completion(2, True), completion(3, False)
    rechecked = ("target", verdict(2, False, "", decision=ready))
    frame = ("observation", accepted(2, False, decision=ready))
    focused = ("popup-focus", {"boot": BOOT, "screen": "Virtual-0"})
    value = {
        "entry-kwin": [("focus", dock(APP)), ("focus", popup(APP)),
                       ("target", verdict(2, True, APP)), ("focus", app_active()), rechecked],
        "entry-shell": [focused, ("keyboard-query", key(2)), ("observation", accepted(2, True)),
                        frame],
        "refusal-kwin": [("focus", dock("")), rechecked, ("focus", popup("")), rechecked,
                         ("target", verdict(3, False, "")), ("focus", desktop_active()),
                         ("target", verdict(3, False, "", decision=refused, reason="refused"))],
        "refusal-shell": [frame, focused, frame, ("keyboard-query", key(3)),
                          ("observation", accepted(3, False)),
                          ("observation", accepted(3, False, decision=refused,
                                                   reason="refused"))],
    }
    return value | changes


def write_run(directory, parts, *, swap_marks=False):
    """Write the logs a keyboard-entry run leaves, with each step's mark at its first line."""
    def lines(rows):
        return [f"qml: layout-probe-{kind} {json.dumps(row)}\n" for kind, row in rows]
    kwin = lines([("focus", app_active())])
    shell = []
    marks = {}
    for step in ("entry", "refusal"):
        marks[step] = {"schema": 1, "shellLines": len(shell), "kwinLines": len(kwin)}
        kwin += lines(parts[f"{step}-kwin"])
        shell += lines(parts[f"{step}-shell"])
    if swap_marks:
        marks["entry"], marks["refusal"] = marks["refusal"], marks["entry"]
    (directory / "kwin.log").write_text("".join(kwin))
    (directory / "plasmashell.log").write_text("".join(shell))
    (directory / "focus-shell-pid.txt").write_text(f"{SHELL_PID}\n")
    (directory / "focus-control.txt").write_text(f"86 28 {BOOT}\n")
    for step, value in marks.items():
        (directory / f"keyboard-entry-mark-{step}.json").write_text(json.dumps(value))


class KeyboardEntrySeedTests(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory(prefix="pf-keyboard-seed-")
        self.addCleanup(scratch.cleanup)
        self.root = Path(scratch.name)
        self.stage = self.root / "build/stage"
        rules = (self.stage
                 / ".local/share/kwin/scripts/plasmafusion-placement/contents/ui/Tiling.js")
        rules.parent.mkdir(parents=True)
        rules.write_text("// private staged rules\n")
        self.output = self.root / "build/seed"

    def run_seed(self, *arguments):
        return subprocess.run(
            [sys.executable, str(PREPARER), "--stage", str(self.stage), "--output",
             str(self.output), *arguments],
            cwd=self.root, capture_output=True, text=True, timeout=10, check=False,
        )

    def test_keyboard_entry_seed_is_a_target_case_with_its_checker_and_scenario(self):
        result = self.run_seed("--keyboard-entry-probe")
        self.assertEqual(result.returncode, 0, result.stderr)
        config = (self.output / ".config/kwinrc").read_text()
        for setting in ("KeyboardEntryProbe=true", "TargetProbe=true", "FocusProbe=true",
                        "TwoBarProbe=false", "CompletionProbe=false", "MixedLifetimeProbe=false",
                        "ViewLossProbe=false", "PipelineProbe=false"):
            self.assertIn(setting, config)
        manifest = json.loads((self.output / "probe-inputs.json").read_text())
        # The checker reuses the mixed checker's line reader.
        for name in ("keyboard_entry.py", "keyboard_scenario.sh", "mixed_lifetime.py",
                     "receipts.py", "cleanup.py"):
            copied = (self.output / ".local/lib/layout-control" / name).read_bytes()
            self.assertEqual(copied, (HERE / name).read_bytes())
            self.assertEqual(manifest[name], hashlib.sha256(copied).hexdigest())

    def test_other_seeds_keep_the_keyboard_entry_case_off(self):
        for flags in ((), ("--target-probe",), ("--two-bar-probe",)):
            with self.subTest(flags=flags):
                result = self.run_seed(*flags)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("KeyboardEntryProbe=false",
                              (self.output / ".config/kwinrc").read_text())
                manifest = json.loads((self.output / "probe-inputs.json").read_text())
                for name in ("keyboard_entry.py", "keyboard_scenario.sh"):
                    self.assertNotIn(name, manifest)
                shutil.rmtree(self.output)

    def test_keyboard_entry_case_is_separate_from_the_other_private_cases(self):
        for extra in (("--two-bar-probe",), ("--completion-probe",), ("--mixed-lifetime-probe",),
                      ("--view-loss-probe",), ("--refused-backend-probe",),
                      ("--pipeline-probe",), ("--drop-retirement-frame",),
                      ("--query-timeout-ms", "200", "--reply-delay-ms", "2000")):
            with self.subTest(extra=extra):
                result = self.run_seed("--keyboard-entry-probe", *extra)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("keyboard-entry case", result.stderr)
                self.assertFalse(self.output.exists())

    def test_keyboard_entry_seed_preparation_is_not_a_result_check(self):
        result = subprocess.run(
            [sys.executable, str(PREPARER), "--check-result", str(self.root),
             "--keyboard-entry-probe"],
            cwd=self.root, capture_output=True, text=True, timeout=10, check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("cannot be combined", result.stderr)


class KeyboardEntryScenarioTests(unittest.TestCase):
    def test_bridge_branches_before_any_pointer_opens_the_popup(self):
        bridge = (HERE / "scenario-bridge.sh").read_text()
        context = bridge.index('        wait_target_context "$focus_boot" pf.focus.alpha\n')
        pointer = bridge.index('pfinput "click $focus_x $focus_y"')
        branch = bridge.index("--key KeyboardEntryProbe")
        sourced = bridge.index('source "$HOME/.local/lib/layout-control/keyboard_scenario.sh"')
        self.assertLess(context, branch)
        self.assertLess(branch, sourced)
        cursor = sourced
        for item in ("finish_probe_session", "return 0"):
            cursor = bridge.index(item, cursor)
        self.assertLess(cursor, pointer)

    def test_each_key_follows_the_state_it_needs(self):
        scenario = (HERE / "keyboard_scenario.sh").read_text()
        capture = "generation=$(python3"
        order = [
            'p.widgets("org.plasmafusion.layoutprobe").length === 0', "p.remove()",
            "keyboard-panels.txt", 'wait_target_context "$focus_boot" pf.focus.alpha',
            "keyboard_mark entry", capture, "previous=$(keyboard_request)",
            'pfinput "key meta+alt+p"', "keyboard_wait dock pf.focus.alpha",
            'wait_target_settled "$focus_boot" $((generation + 1))', 'pfinput "key space"',
            "keyboard_wait popup pf.focus.alpha", 'pfinput "key space"',
            'wait_target_reply "$focus_boot" prepare true "$previous" pf.focus.alpha',
            "PASS: keyboard entry after panel focus prepares the remembered app",
            'pfinput "key esc"', "printf 'quit\\n' >&\"$focus_input\"", 'wait "$focus_client"',
            "keyboard_forgotten", "keyboard_mark refusal", capture, 'pfinput "key meta+alt+p"',
            "keyboard_wait dock -", 'wait_target_settled "$focus_boot" $((generation + 1))',
            'pfinput "key space"', "keyboard_wait popup -", 'pfinput "key space"',
            'wait_target_reply "$focus_boot" prepare false "$target_request" -',
            "PASS: keyboard entry without an eligible app refuses safely",
            'pfinput "key esc"', '"$keyboard_helper" receipt "$OUT"']
        cursor = 0
        for item in order:
            with self.subTest(item=item):
                cursor = scenario.index(item, cursor)
        self.assertRegex(scenario, re.compile(r"^set -euo pipefail$", re.M))
        for forbidden in ("kwriteconfig", "reconfigure", "systemctl", "ssh ", "sudo", "podman",
                          "removeDesktop", "setCurrentDesktop", "pfinput \"click"):
            self.assertNotIn(forbidden, scenario)
        guard = scenario[:scenario.index("keyboard_mark()")]
        for requirement in ("/var/tmp/pfv-layout-control-*", "PF_LAYOUT_PRIVATE_CONTAINER",
                            "/run/.containerenv"):
            self.assertIn(requirement, guard)


class KeyboardEntryCheckerTests(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory(prefix="pf-keyboard-check-")
        self.addCleanup(scratch.cleanup)
        self.output = Path(scratch.name)

    def check(self, **changes):
        swap = changes.pop("swap_marks", False)
        write_run(self.output, steps(**changes), swap_marks=swap)
        checker().check_keyboard_entry(self.output)

    def test_a_complete_keyboard_entry_run_passes(self):
        self.check()

    def test_the_panel_must_have_keyboard_focus_with_the_expected_app(self):
        cases = {
            "the popup opened from the app": (
                {"entry-kwin": [("focus", popup(APP)), ("target", verdict(2, True, APP))]},
                "never had keyboard focus"),
            "a dock the shell does not own": (
                {"entry-kwin": [("focus", dock(APP, pid=999)), ("focus", popup(APP)),
                                ("target", verdict(2, True, APP))]}, "never had keyboard focus"),
            "the panel forgot the app": (
                {"entry-kwin": [("focus", dock("")), ("focus", popup(APP)),
                                ("target", verdict(2, True, APP))]}, "panel's activation"),
            "the refusal's panel still remembers it": (
                {"refusal-kwin": [("focus", dock(APP)), ("focus", popup("")),
                                  ("target", verdict(3, False, ""))]}, "panel's activation"),
        }
        for case, (change, message) in cases.items():
            with self.subTest(case=case):
                with self.assertRaisesRegex(ValueError, message):
                    self.check(**change)

    def test_the_popup_must_open_right_after_the_panel(self):
        cases = {
            "the app in between": ([("focus", dock(APP)), ("focus", app_active()),
                                    ("focus", popup(APP)), ("target", verdict(2, True, APP))],
                                   "right after the panel"),
            "no popup": ([("focus", dock(APP)), ("target", verdict(2, True, APP))],
                         "right after the panel"),
            "the popup forgot the app": ([("focus", dock(APP)), ("focus", popup("")),
                                          ("target", verdict(2, True, APP))],
                                         "popup's activation"),
        }
        for case, (rows, message) in cases.items():
            with self.subTest(case=case):
                with self.assertRaisesRegex(ValueError, message):
                    self.check(**{"entry-kwin": rows})

    def test_one_keyboard_preparation_after_the_popup_took_focus(self):
        focused = ("popup-focus", {"boot": BOOT, "screen": "Virtual-0"})
        cases = {
            "no popup focus": ([("keyboard-query", key(2)), ("observation", accepted(2, True))],
                               "never took keyboard focus"),
            "the key before the focus": ([("keyboard-query", key(2)), focused,
                                          ("observation", accepted(2, True))],
                                         "one keyboard preparation"),
            "two keys": ([focused, ("keyboard-query", key(2)), ("keyboard-query", key(4)),
                          ("observation", accepted(2, True))], "one keyboard preparation"),
            "a pointer validation instead": (
                [focused, ("keyboard-query", key(2) | {"intent": "validate"}),
                 ("observation", accepted(2, True))], "one keyboard preparation"),
        }
        for case, (rows, message) in cases.items():
            with self.subTest(case=case):
                with self.assertRaisesRegex(ValueError, message):
                    self.check(**{"entry-shell": rows})

    def test_the_native_verdicts_prepare_the_app_and_then_refuse(self):
        entry = [("focus", dock(APP)), ("focus", popup(APP))]
        refusal = [("focus", dock("")), ("focus", popup(""))]
        cases = {
            "entry refused": ({"entry-kwin": entry + [("target", verdict(2, False, ""))]},
                              "did not prepare the remembered app"),
            "entry names the shell": (
                {"entry-kwin": entry + [("target", verdict(2, True, "org.kde.plasmashell"))]},
                "did not prepare the remembered app"),
            "no entry verdict": ({"entry-kwin": entry}, "no native verdict"),
            "refusal ready": ({"refusal-kwin": refusal + [("target", verdict(3, True, APP))]},
                              "not refused with no target"),
            "refusal names a target": (
                {"refusal-kwin": refusal + [("target", verdict(3, False, APP))]},
                "not refused with no target"),
        }
        for case, (change, message) in cases.items():
            with self.subTest(case=case):
                with self.assertRaisesRegex(ValueError, message):
                    self.check(**change)

    def test_the_verdict_must_be_given_in_the_popup_the_panel_opened(self):
        answer = ("target", verdict(2, True, APP))
        cases = {
            "in a later popup opened from the app": [
                ("focus", dock(APP)), ("focus", popup(APP)), ("focus", app_active()),
                ("focus", popup(APP)), answer],
            "before the popup opened": [("focus", dock(APP)), answer, ("focus", popup(APP))],
        }
        for case, rows in cases.items():
            with self.subTest(case=case):
                with self.assertRaisesRegex(ValueError, "popup the panel opened"):
                    self.check(**{"entry-kwin": rows})

    def test_the_first_verdict_must_decide_the_completion(self):
        entry = [("focus", dock(APP)), ("focus", popup(APP))]
        cases = {
            "an early return first": ("refusal-kwin", [
                ("focus", dock("")), ("focus", popup("")),
                ("target", verdict(3, False, "", decision=None, reason="unavailable")),
                ("target", verdict(3, False, ""))]),
            "a completion that disagrees": ("entry-kwin", entry + [
                ("target", verdict(2, True, APP, decision=completion(2, False)))]),
            "another request's completion": ("entry-kwin", entry + [
                ("target", verdict(2, True, APP, decision=completion(1, True)))]),
        }
        for case, (step, rows) in cases.items():
            with self.subTest(case=case):
                with self.assertRaisesRegex(ValueError, "did not decide"):
                    self.check(**{step: rows})

    def test_the_deciding_completion_restates_its_answer(self):
        # A frame carrying it is accepted, so only the restatement check can reject these.
        focused = ("popup-focus", {"boot": BOOT, "screen": "Virtual-0"})
        ready = completion(2, True)
        frame = ("observation", accepted(2, False, decision=ready))
        rechecked = ("target", verdict(2, False, "", decision=ready))
        handleless = ready | {"token": ""}

        def refusal(decided):
            # The first verdict refuses as stale-context; the completion says otherwise.
            return {"refusal-kwin": [("focus", dock("")), rechecked, ("focus", popup("")),
                                     rechecked,
                                     ("target", verdict(3, False, "", decision=decided))],
                    "refusal-shell": [frame, focused, frame, ("keyboard-query", key(3)),
                                      ("observation", accepted(3, False, decision=decided))]}
        cases = {
            "a stale-context refusal decided as busy": refusal(
                completion(3, False) | {"reason": "busy"}),
            "a refusal decided with a handle": refusal(completion(3, False) | {"token": "t"}),
            "an acceptance decided without its handle": {
                "entry-kwin": [("focus", dock(APP)), ("focus", popup(APP)),
                               ("target", verdict(2, True, APP, decision=handleless))],
                "entry-shell": [focused, ("keyboard-query", key(2)),
                                ("observation", accepted(2, True, decision=handleless))]},
        }
        for case, change in cases.items():
            with self.subTest(case=case):
                with self.assertRaisesRegex(ValueError, "did not decide"):
                    self.check(**change)

    def test_the_consumer_must_accept_the_answer(self):
        focused = ("popup-focus", {"boot": BOOT, "screen": "Virtual-0"})
        for case, rows in {
            "not accepted": [focused, ("keyboard-query", key(2))],
            "accepted the other way": [focused, ("keyboard-query", key(2)),
                                       ("observation", accepted(2, False))],
            "a frame with another completion": [
                focused, ("keyboard-query", key(2)),
                ("observation", accepted(2, True, decision=completion(2, False)))],
        }.items():
            with self.subTest(case=case):
                with self.assertRaisesRegex(ValueError, "did not accept"):
                    self.check(**{"entry-shell": rows})

    def test_no_verdict_anywhere_names_a_shell_surface(self):
        rows = [("focus", dock("")), ("focus", popup("")), ("target", verdict(3, False, "")),
                ("target", verdict(5, True, "org.kde.plasmashell"))]
        with self.assertRaisesRegex(ValueError, "other than the controlled app"):
            self.check(**{"refusal-kwin": rows})

    def test_the_steps_must_be_in_order_and_marked(self):
        with self.assertRaisesRegex(ValueError, "out of order"):
            self.check(swap_marks=True)
        with self.assertRaisesRegex(ValueError, "unknown keyboard-entry mark"):
            checker().mark(self.output, "other")

    def test_the_receipt_is_written_only_after_the_check(self):
        write_run(self.output, steps(**{"refusal-kwin": [("focus", dock("")),
                                                         ("focus", popup(""))]}))
        with self.assertRaises(ValueError):
            checker().write_receipt(self.output)
        self.assertFalse((self.output / "keyboard-entry-result.json").exists())
        write_run(self.output, steps())
        checker().write_receipt(self.output)
        self.assertEqual(json.loads((self.output / "keyboard-entry-result.json").read_text()),
                         {"schema": 1, "passed": True, "checks": checker().CHECKS})
        with self.assertRaises(FileExistsError):
            checker().write_receipt(self.output)

    def test_check_result_runs_the_keyboard_entry_checker(self):
        # The cleanup fixture empties the logs, so the run's logs are written after it.
        write_cleanup_fixture(self.output)
        write_run(self.output, steps())
        (self.output / "scenario.log").write_text("scenario rc=0\nsession rc=0\n")
        (self.output / "keyboard-entry-result.json").write_text(json.dumps({
            "schema": 1, "passed": True,
            "checks": ["roundtrip-native", "panel-keyboard-entry", "safe-refusal"]}))
        command = [sys.executable, str(PREPARER), "--check-result", str(self.output),
                   "--scope", "keyboard-entry"]
        passed = subprocess.run(command, capture_output=True, text=True, timeout=30,
                                check=False)
        self.assertEqual(passed.returncode, 0, passed.stderr)
        # The receipt alone is not enough: the raw evidence is checked again.
        write_run(self.output, steps(**{"entry-kwin": [("focus", popup(APP)),
                                                       ("target", verdict(2, True, APP))]}))
        failed = subprocess.run(command, capture_output=True, text=True, timeout=30,
                                check=False)
        self.assertNotEqual(failed.returncode, 0)
        self.assertIn("never had keyboard focus", failed.stderr)


if __name__ == "__main__":
    unittest.main()
