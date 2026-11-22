# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Two-bar cases: probe widgets on two bars for different views, with competing requests."""

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
    from .completion_tests import CompletionRun, prepare, query, refused
else:
    from cleanup_tests import write_cleanup_fixture
    from completion_tests import CompletionRun, prepare, query, refused

HERE = Path(__file__).resolve().parent
PREPARER = HERE / "prepare_seed.py"


def checker():
    """Import lazily: a missing checker fails these cases, not the whole entry point."""
    name = f"{__package__}.two_bar" if __package__ else "two_bar"
    return importlib.import_module(name)


class TwoBarSeedTests(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory(prefix="pf-two-bar-seed-")
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

    def test_two_bar_seed_is_a_target_case_with_its_checker_and_scenario(self):
        result = self.run_seed("--two-bar-probe")
        self.assertEqual(result.returncode, 0, result.stderr)
        config = (self.output / ".config/kwinrc").read_text()
        for setting in ("TwoBarProbe=true", "TargetProbe=true", "FocusProbe=true",
                        "CompletionProbe=false", "MixedLifetimeProbe=false",
                        "ViewLossProbe=false", "PipelineProbe=false"):
            self.assertIn(setting, config)
        manifest = json.loads((self.output / "probe-inputs.json").read_text())
        # The checker reuses the completion rules and the mixed checker's line reader.
        for name in ("two_bar.py", "two_bar_scenario.sh", "completion.py", "mixed_lifetime.py",
                     "receipts.py", "cleanup.py"):
            copied = (self.output / ".local/lib/layout-control" / name).read_bytes()
            self.assertEqual(copied, (HERE / name).read_bytes())
            self.assertEqual(manifest[name], hashlib.sha256(copied).hexdigest())

    def test_other_seeds_keep_the_two_bar_case_off(self):
        for flags in ((), ("--target-probe",), ("--completion-probe",)):
            with self.subTest(flags=flags):
                result = self.run_seed(*flags)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("TwoBarProbe=false", (self.output / ".config/kwinrc").read_text())
                manifest = json.loads((self.output / "probe-inputs.json").read_text())
                for name in ("two_bar.py", "two_bar_scenario.sh"):
                    self.assertNotIn(name, manifest)
                shutil.rmtree(self.output)

    def test_two_bar_case_is_separate_from_the_other_private_cases(self):
        for extra in (("--completion-probe",), ("--mixed-lifetime-probe",),
                      ("--view-loss-probe",), ("--refused-backend-probe",),
                      ("--pipeline-probe",), ("--drop-retirement-frame",),
                      ("--query-timeout-ms", "200", "--reply-delay-ms", "2000")):
            with self.subTest(extra=extra):
                result = self.run_seed("--two-bar-probe", *extra)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("two-bar case", result.stderr)
                self.assertFalse(self.output.exists())

    def test_two_bar_seed_preparation_is_not_a_result_check(self):
        result = subprocess.run(
            [sys.executable, str(PREPARER), "--check-result", str(self.root), "--two-bar-probe"],
            cwd=self.root, capture_output=True, text=True, timeout=10, check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("cannot be combined", result.stderr)


class TwoBarScenarioTests(unittest.TestCase):
    def test_bridge_puts_one_probe_bar_on_each_of_two_outputs(self):
        bridge = (HERE / "scenario-bridge.sh").read_text()
        branch = bridge.index("--key TwoBarProbe")
        created = bridge.index('evaljs - >"$OUT/widgets-created.txt"', branch)
        online = bridge.index("wait_for_phase online", branch)
        self.assertLess(created, online)
        section = bridge[branch:online]
        # Two outputs first; then one probe widget on a panel left on screen 0 and one on a
        # second panel moved to screen 1.
        self.assertIn("kscreen-doctor -o", section)
        self.assertIn("[[ $outputs -ge 2 ]] || {", section)
        two_bars = section[:section.index("else")]
        order = ['var p=new Panel;', 'p.addWidget("org.plasmafusion.layoutprobe")',
                 'var q=new Panel;']
        cursor = 0
        for item in order:
            cursor = two_bars.index(item, cursor)
        self.assertEqual(two_bars.count("addWidget("), 2)
        self.assertNotIn("p.screen", two_bars)
        for item in ('q.screen=1;', 'q.addWidget("org.plasmafusion.layoutprobe")'):
            self.assertIn(item, two_bars[cursor:])
        # Neither panel floats, so a control does not move after it reported its position.
        self.assertIn("p.floating=false;", two_bars[:cursor])
        self.assertIn("q.floating=false;", two_bars[cursor:])

    def test_bridge_branches_after_the_first_accepted_preparation(self):
        bridge = (HERE / "scenario-bridge.sh").read_text()
        prepared = bridge.index('target_prepare_request=$(wait_target_reply "$focus_boot" '
                                'prepare true 1 pf.focus.alpha)')
        branch = bridge.index("--key TwoBarProbe", prepared)
        sourced = bridge.index('source "$HOME/.local/lib/layout-control/two_bar_scenario.sh"')
        validate = bridge.index('pfinput "key space"', prepared)
        self.assertLess(prepared, branch)
        self.assertLess(branch, sourced)
        self.assertLess(sourced, validate)
        cursor = sourced
        for item in ("printf 'quit\\n' >&\"$focus_input\"", 'wait "$focus_client"',
                     "finish_probe_session", "return 0"):
            cursor = bridge.index(item, cursor)
        self.assertLess(cursor, validate)

    def test_each_step_is_marked_before_the_action_it_checks(self):
        scenario = (HERE / "two_bar_scenario.sh").read_text()
        order = ["two_bar_subject holder", "two_bar_subject other", "two_bar_wait bars",
                 "two-bar-other-control.txt", 'pfinput "key esc"',
                 'pfinput "click $desktop_x $desktop_y"', "heldclient.py", "pf.focus.beta",
                 'pfinput "click $other_x $other_y"', "two_bar_mark competitor",
                 'pfinput "key space"', "two_bar_wait competitor", "holder.remove()",
                 'evaljs "$OUT/two-bar-remove.js"', "two_bar_mark retired", "invokeShortcut",
                 "two_bar_wait retired", 'pfinput "key esc"', 'pfinput "click $beta_x $beta_y"',
                 'pfinput "click $other_x $other_y"', "two_bar_mark explicit",
                 'pfinput "key space"', "two_bar_wait explicit", '"$two_bar_helper" receipt "$OUT"']
        cursor = 0
        for item in order:
            cursor = scenario.index(item, cursor)
        self.assertRegex(scenario, re.compile(r"^set -euo pipefail$", re.M))
        for forbidden in ("kwriteconfig", "reconfigure", "systemctl", "ssh ", "sudo", "podman",
                          "removeDesktop", "setCurrentDesktop"):
            self.assertNotIn(forbidden, scenario)
        guard = scenario[:scenario.index("two_bar_mark()")]
        for requirement in ("/var/tmp/pfv-layout-control-*", "PF_LAYOUT_PRIVATE_CONTAINER",
                            "/run/.containerenv"):
            self.assertIn(requirement, guard)

    def test_the_other_control_is_read_once_the_bars_outputs_are_confirmed(self):
        # A desktop click below a control still on the first output would open the second app
        # there; the point is read only after the checker saw the outputs differ, and checked.
        scenario = (HERE / "two_bar_scenario.sh").read_text()
        confirmed = scenario.split("two_bar_wait bars", 1)[1].split('pfinput "key esc"', 1)[0]
        self.assertIn('other["screen"] != holder["screen"]', confirmed)
        self.assertIn("read -r other_x other_y desktop_x desktop_y", confirmed)

    def test_the_refusing_popup_stays_open_while_the_slot_is_freed(self):
        # No input between the refusal and the retirement read: the refused request's view is
        # still current then, so a provider that re-evaluated it could grant it.
        scenario = (HERE / "two_bar_scenario.sh").read_text()
        held = scenario.split("two_bar_wait competitor", 1)[1].split("two_bar_wait retired", 1)[0]
        self.assertNotIn("pfinput", held)

    def test_the_holders_bar_is_found_by_its_consumer_and_removed_before_the_mark(self):
        scenario = (HERE / "two_bar_scenario.sh").read_text()
        removal = scenario.split("two_bar_wait competitor", 1)[1].split("two_bar_mark retired",
                                                                    1)[0]
        # The holder's panel is the one whose widget names the holder's consumer; after the
        # removal, the reader's own walk must no longer list that panel or that widget.
        found, removed = removal.split("holder.remove()", 1)
        consumer = "w.readConfig('layoutRequest','{}')).consumer===holder_boot)"
        self.assertIn(consumer + " holder=p;", found)
        for requirement in ("if (p.id===removed) listed=true", consumer + " listed=true;",
                            "listed:listed", '"listed":false}'):
            self.assertIn(requirement, removed)
        self.assertGreater(removed.index("listed:listed"), removed.rindex("p.widgets("))


HOLDER, OTHER = "1795000000001:0.11", "1795000000002:0.22"
EPOCH = "c" * 32
OUTPUTS = {HOLDER: "Virtual-0", OTHER: "Virtual-1"}


def accepted(request, token):
    return {"request": request, "intent": "prepare", "accepted": True, "token": token,
            "reason": ""}


HELD = accepted(2, EPOCH + ":1")
BUSY = refused(2, "busy")
RECOVERED = accepted(3, EPOCH + ":2")


class TwoBarRun(CompletionRun):
    """Synthetic two-bar evidence in the order the native scenario produces it."""

    def __init__(self, root: Path):
        super().__init__(root)
        self.screens = {}

    def control(self, boot: str, screen: str) -> None:
        self.screens[boot] = screen
        self.shell.append("qml: layout-probe-focus-control " + json.dumps({
            "boot": boot, "x": 86 if screen == "Virtual-0" else 1526, "y": 23, "screen": screen,
            "validateX": 300, "validateY": 23}) + "\n")

    def publish(self, *frames, started=True, finished=True, **options) -> None:
        # The provider logs the start of the read that a publication answers, and that read's
        # end after the publication.
        if started:
            self.kwin.append("qml: layout-probe: read started\n")
        super().publish(*frames, **options)
        if finished:
            self.kwin.append("qml: layout-probe: read finished\n")
        # A consumer reports its control again after every frame it accepts.
        for frame in frames:
            if not frame.get("missed") and frame["boot"] in self.screens:
                self.control(frame["boot"], self.screens[frame["boot"]])

    def on(self, frame: dict, output: str | None = None) -> dict:
        """The frame with the view context the provider publishes to that consumer."""
        boot = frame["boot"]
        return dict(frame, context={
            "epoch": EPOCH, "generation": 0, "desktopId": "desktop", "activityId": "activity",
            "outputName": output or OUTPUTS[boot],
            "consumerLease": EPOCH + (":1" if boot == HOLDER else ":2")})

    def subject(self, role: str, boot: str) -> None:
        (self.root / f"two-bar-subject-{role}.json").write_text(json.dumps({"schema": 1,
                                                                            "boot": boot}))

    def mark(self, label: str) -> None:
        self.flush()
        checker().mark(self.root, label)

    def step(self, name: str) -> dict:
        self.flush()
        return checker().record_step(self.root, name)

    def build(self, *, same_output=False, no_control=False, no_view=False, refresh=False,
              wrong_view=False, holder_refused=False, holder_unseen=False, second_start=False,
              two_lifetimes=False, overwrite=False, holder_missing=False, view_changed=False,
              in_flight=False, holder_after=False, no_read_after=False, promoted=False,
              retired_missed=False, retired_request=False, holder_again=False,
              wrong_class=False, wrong_output=False, recovery_missed=False, drift=False,
              mismatch=False, busy_missed=False, unpublished=False, silent_read=False,
              unread=False, stale_read=False, viewless_recovery=False,
              advanced_holder=False) -> None:
        # The other bar's query when the case begins: its first request, or its second after a
        # refresh. Its preparations follow that number.
        first = 2 if refresh else 1
        self.control(HOLDER, "Virtual-0")
        if refresh:
            # Its first request went out before its bar reached its output, so the answer names
            # the old one; the bar then reports its output and refreshes.
            self.publish(self.on(query(HOLDER, 1)), self.on(query(OTHER, 1), "Virtual-0"))
            self.control(OTHER, "Virtual-1")
        elif not no_control:
            self.control(OTHER, "Virtual-0" if same_output else "Virtual-1")
        self.subject("holder", HOLDER)
        self.subject("other", OTHER)
        waiting = query(OTHER, first) if no_view else self.on(query(OTHER, first))
        self.publish(self.on(query(HOLDER, 1)), waiting)
        # The holder's preparation, accepted in the prelude, with the app on its output.
        decided = prepare(HOLDER, 2, ready=True, token=EPOCH + ":1", completion=HELD)
        if holder_refused:
            decided = prepare(HOLDER, 2, reason="popup-focus-unconfirmed",
                              completion=refused(2, "popup-focus-unconfirmed"))
        self.publish(dict(self.on(decided), missed=holder_unseen), waiting)
        self.step("bars")
        if second_start:
            self.kwin.append("qml: layout-probe: initialized true -1\n")
        held = self.on(prepare(HOLDER, 2, completion=HELD))
        for opening in range(3):
            # Esc, the second app on the other output, and the other bar's menu opening.
            self.context()
            other = self.on(query(OTHER, first),
                            "Virtual-0" if wrong_view and opening == 1 else None)
            kept = held
            if drift and opening == 0:
                # A newer frame changes the holder's decided completion.
                kept = self.on(prepare(HOLDER, 2, completion=refused(2, "stale-context")))
            if mismatch and opening == 0:
                # The verdict reports the target no longer valid; the received frame says ready.
                kept = dict(held, received={"ready": True, "reason": "", "token": EPOCH + ":1"})
            self.publish(kept, other, epoch="d" * 32 if two_lifetimes and opening == 2 else EPOCH)
        if advanced_holder:
            # A newer holder request the provider handled: request 2 may then drop its completion.
            self.publish(self.on(dict(prepare(HOLDER, 3, reason="focus-changed", completion=None),
                                      intent="validate")))
        self.mark("competitor")
        busy = self.on(prepare(OTHER, first + 1, completion=refused(first + 1, "busy"),
                               reason="busy"))
        decision = busy
        if overwrite:
            # What one global slot that a second bar can overwrite would answer.
            decision = self.on(dict(prepare(OTHER, first + 1, ready=True, token=EPOCH + ":2",
                                            completion=accepted(first + 1, EPOCH + ":2")),
                                    **{"class": "pf.focus.beta"}))
        holder_row = held
        if advanced_holder:
            holder_row = self.on(prepare(HOLDER, 2, reason="stale-or-conflicting-request",
                                         completion=None))
        self.publish(*(() if holder_missing else (holder_row,)),
                     dict(decision, missed=busy_missed))
        self.step("competitor")
        if in_flight or retired_missed:
            # A read already under way at the removal still answers the holder after the mark.
            self.kwin.append("qml: layout-probe: read started\n")
        if stale_read:
            # A read that ended without publishing just before the mark, then a publication
            # after it that no read of its own produced.
            self.kwin.append("qml: layout-probe: read started\n")
            self.kwin.append("qml: layout-probe: read finished\n")
        self.mark("retired")
        if stale_read:
            self.publish(held, busy, started=False, finished=False)
        if in_flight or retired_missed:
            self.publish(held, busy, started=False)
        if view_changed:
            # The refused request's view changes before the slot is freed.
            self.context()
        if unread:
            # A publication after the removal that no read of its own preceded, still answering
            # the holder, as a provider publishing cached rows on a wake-up would.
            self.publish(held, busy, started=False, finished=False)
        if silent_read:
            # A read after the removal that ends without publishing answers nobody.
            self.kwin.append("qml: layout-probe: read started\n")
            self.kwin.append("qml: layout-probe: read finished\n")
        if holder_after:
            # A read started after the removal still answers the holder.
            self.publish(held, busy)
        elif unpublished:
            # A read started after the removal has not published yet.
            self.kwin.append("qml: layout-probe: read started\n")
        elif promoted:
            self.publish(dict(busy, ready=True, reason="", token=EPOCH + ":2"))
        elif retired_missed:
            # The read without the holder is published, but the other bar never receives it.
            self.publish(dict(busy, missed=True))
        elif retired_request:
            # The other bar has already sent a newer request, which is still unanswered.
            self.publish(self.on(prepare(OTHER, first + 2, reason="unavailable",
                                         completion=None)))
        elif not no_read_after:
            self.publish(busy)
        self.step("retired")
        self.context()
        self.publish(*((held,) if holder_again else ()), busy)
        self.mark("explicit")
        recovered = dict(prepare(OTHER, first + 2, ready=True, token=EPOCH + ":2",
                                 completion=accepted(first + 2, EPOCH + ":2")),
                         **{"class": "pf.focus.alpha" if wrong_class else "pf.focus.beta"})
        if not viewless_recovery:
            recovered = self.on(recovered, "Virtual-0" if wrong_output else None)
        self.publish(dict(recovered, missed=recovery_missed))
        self.step("explicit")


class TwoBarCheckerTests(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory(prefix="pf-two-bar-check-")
        self.addCleanup(scratch.cleanup)
        self.root = Path(scratch.name)
        write_cleanup_fixture(self.root)
        self.run_ = TwoBarRun(self.root)

    def assert_rejected(self, message: str, **variant) -> None:
        with self.assertRaisesRegex(ValueError, message):
            self.run_.build(**variant)
            checker().write_receipt(self.root)
        self.assertFalse((self.root / "two-bar-result.json").exists())

    def test_two_bars_pass_and_record_each_decision(self):
        self.run_.build()
        checker().write_receipt(self.root)
        receipt = json.loads((self.root / "two-bar-result.json").read_text())
        self.assertEqual(receipt, {"schema": 1, "passed": True, "checks": checker().CHECKS})
        bars = json.loads((self.root / "two-bar-bars.json").read_text())
        self.assertEqual(bars["outputs"], {"holder": "Virtual-0", "other": "Virtual-1"})
        competitor = json.loads((self.root / "two-bar-competitor.json").read_text())
        self.assertEqual(competitor["other"]["completion"], BUSY)
        explicit = json.loads((self.root / "two-bar-explicit.json").read_text())
        self.assertEqual(explicit["other"]["completion"], RECOVERED)
        with self.assertRaises(OSError):
            checker().write_receipt(self.root)

    def test_two_bars_on_one_output_fail(self):
        self.assert_rejected("one output", same_output=True)

    def test_a_frame_for_another_bars_view_fails(self):
        self.assert_rejected("another bar's view", wrong_view=True)

    def test_a_second_bar_that_takes_the_held_slot_fails(self):
        self.assert_rejected("busy", overwrite=True)

    def test_the_competing_decision_must_also_carry_the_holders_completion(self):
        self.assert_rejected("holder's completion", holder_missing=True)

    def test_a_holder_frame_without_its_completion_cannot_stand_for_one_that_keeps_it(self):
        # Once the holder has a newer handled request, a replay of request 2 may drop the
        # completion; it then cannot show that the busy publication kept it.
        self.assert_rejected("keeping the holder's completion", advanced_holder=True)

    def test_a_holder_that_is_still_read_after_its_bar_is_removed_fails(self):
        self.assert_rejected("not retired", holder_after=True)

    def test_a_read_must_follow_the_holders_retirement(self):
        self.assert_rejected("no read after", no_read_after=True)

    def test_a_repeated_busy_intent_must_not_be_promoted(self):
        self.assert_rejected("promoted", promoted=True)

    def test_the_other_bar_must_accept_a_frame_after_the_holders_retirement(self):
        self.assert_rejected("no frame after", retired_missed=True)

    def test_the_slot_must_be_freed_while_the_refused_view_is_current(self):
        self.assert_rejected("view changed", view_changed=True)

    def test_the_explicit_recovery_must_capture_the_app_on_its_own_output(self):
        self.assert_rejected("pf.focus.beta", wrong_class=True)

    def test_the_explicit_recovery_must_report_its_own_bars_view(self):
        self.assert_rejected("another bar's view", wrong_output=True)

    def test_the_explicit_recovery_must_carry_its_own_bars_view(self):
        # check_views skips a frame without a view, and the other bar's earlier frames had one.
        self.assert_rejected("accepted with its own view", viewless_recovery=True)

    def test_a_second_provider_start_fails(self):
        self.assert_rejected("one provider lifetime", second_start=True)

    def test_frames_from_another_provider_lifetime_fail(self):
        self.assert_rejected("one provider lifetime: frames", two_lifetimes=True)

    def test_the_completion_rules_apply_to_both_bars(self):
        self.assert_rejected("a completion changed after its decision", drift=True)

    def test_received_frames_must_match_their_native_verdicts(self):
        self.assert_rejected("does not match its native verdict", mismatch=True)

    def test_the_other_bar_must_accept_a_frame_carrying_its_refusal(self):
        self.assert_rejected("never accepted a frame carrying its refusal", busy_missed=True)

    def test_a_bar_that_never_reported_its_output_fails(self):
        self.assert_rejected("never reported its output", no_control=True)

    def test_a_bar_without_a_frame_for_its_own_view_fails(self):
        self.assert_rejected("never accepted a frame for its own view", no_view=True)

    def test_a_request_sent_before_the_bar_reached_its_output_may_name_the_old_one(self):
        # As in the native run: the other bar's first request still named output 0, and its
        # answer came before the bar reported its output and refreshed once.
        self.run_.build(refresh=True)
        checker().write_receipt(self.root)
        competitor = json.loads((self.root / "two-bar-competitor.json").read_text())
        self.assertEqual(competitor["other"]["completion"], refused(3, "busy"))

    def test_the_holders_first_preparation_must_be_accepted(self):
        self.assert_rejected("first preparation was not accepted", holder_refused=True)

    def test_the_holder_must_accept_a_frame_carrying_its_completion(self):
        self.assert_rejected("holder never accepted", holder_unseen=True)

    def test_a_read_under_way_at_the_removal_may_still_answer_the_holder(self):
        self.run_.build(in_flight=True)
        checker().write_receipt(self.root)
        self.assertTrue((self.root / "two-bar-result.json").is_file())

    def test_a_holder_answered_again_after_its_retirement_fails(self):
        self.assert_rejected("not retired", holder_again=True)

    def test_the_read_after_the_removal_must_be_published(self):
        self.assert_rejected("not been published", unpublished=True)

    def test_a_read_after_the_removal_that_publishes_nothing_is_skipped(self):
        self.run_.build(silent_read=True)
        checker().write_receipt(self.root)
        self.assertTrue((self.root / "two-bar-result.json").is_file())

    def test_a_publication_without_a_read_of_its_own_fails(self):
        self.assert_rejected("followed no read of its own", unread=True)

    def test_an_ended_read_cannot_stand_for_a_publication_without_one(self):
        self.assert_rejected("followed no read of its own", stale_read=True)

    def test_the_retirement_read_must_answer_the_refused_request(self):
        self.assert_rejected("did not answer the other bar's refusal", retired_request=True)

    def test_the_other_bar_must_accept_its_new_completion(self):
        self.assert_rejected("new completion", recovery_missed=True)

    def test_an_unknown_mark_is_refused(self):
        with self.assertRaisesRegex(ValueError, "unknown two-bar mark"):
            checker().mark(self.root, "bars")

    def test_an_invalid_subject_record_fails(self):
        self.run_.build()
        (self.root / "two-bar-subject-other.json").write_text(
            json.dumps({"schema": 1, "boot": OTHER, "role": "other"}))
        with self.assertRaisesRegex(ValueError, "invalid two-bar other record"):
            checker().write_receipt(self.root)

    def test_a_mark_beyond_its_steps_evidence_fails(self):
        self.run_.build()
        mark = self.root / "two-bar-mark-explicit.json"
        mark.write_text(json.dumps(json.loads(mark.read_text()) | {"kwinLines": 10 ** 6}))
        with self.assertRaisesRegex(ValueError, "invalid two-bar evidence window"):
            checker().write_receipt(self.root)

    def test_a_record_end_beyond_the_logs_fails(self):
        self.run_.build()
        record = self.root / "two-bar-bars.json"
        value = json.loads(record.read_text())
        value["end"]["kwinLines"] = 10 ** 6
        record.write_text(json.dumps(value))
        with self.assertRaisesRegex(ValueError, "invalid two-bar evidence end"):
            checker().write_receipt(self.root)

    def test_a_malformed_control_report_fails(self):
        self.run_.shell.append('qml: layout-probe-focus-control {"boot": "x", "screen": 1}\n')
        self.assert_rejected("malformed focus control")

    def test_marks_and_step_records_are_written_once(self):
        self.run_.build()
        with self.assertRaises(FileExistsError):
            checker().mark(self.root, "competitor")
        with self.assertRaises(FileExistsError):
            checker().record_step(self.root, "explicit")

    def test_a_tampered_record_fails_recomputation(self):
        self.run_.build()
        record = self.root / "two-bar-retired.json"
        value = json.loads(record.read_text())
        value["revision"] += 1
        record.write_text(json.dumps(value))
        with self.assertRaisesRegex(ValueError, "does not match its raw evidence"):
            checker().write_receipt(self.root)

    def test_the_receipt_requires_every_step(self):
        self.run_.build()
        (self.root / "two-bar-explicit.json").unlink()
        with self.assertRaises(OSError):
            checker().write_receipt(self.root)
        self.assertFalse((self.root / "two-bar-result.json").exists())

    def test_check_result_requires_the_receipt_and_rechecks_the_evidence(self):
        self.run_.build()
        (self.root / "scenario.log").write_text("scenario rc=0\nsession rc=0\n")
        check = [sys.executable, str(PREPARER), "--check-result", str(self.root),
                 "--scope", "two-bar"]
        missing = subprocess.run(check, capture_output=True, text=True, timeout=10, check=False)
        self.assertNotEqual(missing.returncode, 0)
        self.assertIn("missing probe receipt", missing.stderr)
        checker().write_receipt(self.root)
        passed = subprocess.run(check, capture_output=True, text=True, timeout=10, check=False)
        self.assertEqual(passed.returncode, 0, passed.stderr)
        record = self.root / "two-bar-competitor.json"
        value = json.loads(record.read_text())
        value["holderRevision"] = 0
        record.write_text(json.dumps(value))
        tampered = subprocess.run(check, capture_output=True, text=True, timeout=10, check=False)
        self.assertNotEqual(tampered.returncode, 0)
        self.assertIn("does not match its raw evidence", tampered.stderr)


if __name__ == "__main__":
    unittest.main()
