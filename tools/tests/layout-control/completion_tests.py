# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Completion cases: a prepare's answer, decided once and kept by newer state frames."""

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
    from .qml_helpers import qml_handler
else:
    from cleanup_tests import write_cleanup_fixture
    from qml_helpers import qml_handler

HERE = Path(__file__).resolve().parent
PREPARER = HERE / "prepare_seed.py"


def checker():
    """Import lazily: a missing checker fails these cases, not the whole entry point."""
    name = f"{__package__}.completion" if __package__ else "completion"
    return importlib.import_module(name)


METHODS = ("reconcileTargetConsumers", "targetConsumerFor", "captureTargetConsumerContext",
           "handleTargetRequest", "publish")
# The provider's own publication and request handling, with native state reduced to switches.
PUBLICATION = r"""
const lines = [];
console.info = (name, text) => {
    if (name === 'layout-probe-target') lines.push(JSON.parse(text));
};
console.warn = () => {};
const writer = {service: '', arguments: [], call: () => {}};
const popup = {deleted: false, appletPopup: true, output: {name: 'Virtual-0'}};
const Workspace = {activeWindow: popup};
const Tiling = {alive: window => !!window && window.deleted === false};
const state = {ready: true, generation: 0, focus: true, capture: true, valid: true};
const probe = {
    epoch: 'a'.repeat(32), readOwner: ':1.20', inventoryOwner: '', targetInventoryComplete: false,
    targetConsumers: [], consumerSerial: 0, targetExchange: null, preparedTarget: null,
    preparationFailure: 'not-prepared', targetGeneration: 0, targetSerial: 0, targetProbe: true,
    mixedLifetimeProbe: false, revision: 0, capable: true, refusal: -1, selfOwner: ':1.1',
    identityName: 'alias', competingProviderRejected: true, publishing: false,
    lastEligibleWindow: null,
    invalidateTarget: reason => { probe.preparedTarget = null; probe.preparationFailure = reason; },
    targetContextReady: () => state.ready,
    captureTargetContext: () => state.ready ? {
        epoch: probe.epoch, generation: state.generation, desktopId: 'desktop',
        activityId: 'activity', outputName: 'Virtual-0'
    } : null,
    canUseTargetHandoff: () => false,
    shellOwnsFocus: () => state.focus,
    prepareTarget: () => {
        probe.preparedTarget = state.capture ? {window: 'captured'} : null;
        probe.preparationFailure = state.capture ? '' : 'no-target';
        return state.capture;
    },
    validateTarget: () => {
        if (!state.valid) probe.invalidateTarget('view-changed');
        return state.valid && probe.preparedTarget !== null;
    }
};
const methods = (function(){with(probe){return {
METHODS
};}})();
Object.assign(probe, methods);
probe.reconcileTargetConsumers({complete: true,
                                widgets: [{id: 7, consumer: 'a'}, {id: 8, consumer: 'b'}]});
const lease = {a: probe.targetConsumerFor(7, 'a').lease, b: probe.targetConsumerFor(8, 'b').lease};
const row = (id, consumer, number, intent, extra) => Object.assign({
    version: 1, id, consumer, consumerLease: lease[consumer], request: number, intent,
    outputName: 'Virtual-0', token: '', viewEpoch: probe.epoch, viewGeneration: 0,
    desktopId: 'desktop', activityId: 'activity', viewOutputName: 'Virtual-0'
}, extra || {});
const query = (id, consumer, number) => ({id, consumer, request: number, intent: 'query'});
const frames = [];
const publish = (rows, status) => {
    const before = lines.length;
    probe.publishing = false;
    probe.publish(status || 'online', rows, probe.readOwner);
    const text = writer.arguments[0];
    const messages = JSON.parse(text.slice('var messages = '.length,
                                           text.indexOf(';var written=0;')));
    const result = {packets: messages.map(message => JSON.parse(message.packet)),
                    lines: lines.slice(before)};
    frames.push(result);
    return result;
};
"""


def refused(request, reason):
    return {"request": request, "intent": "prepare", "accepted": False, "token": "",
            "reason": reason}


class CompletionPublicationTests(unittest.TestCase):
    def run_publication(self, action):
        script = PUBLICATION.replace("METHODS", ",".join(
            name + ":" + qml_handler(name, "provider.qml") for name in METHODS)) + action
        result = subprocess.run(["node", "-"], input=script, capture_output=True, text=True,
                                timeout=10, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_accepted_prepare_is_decided_once_and_kept_while_validity_is_rechecked(self):
        out = self.run_publication("""
const prepare = row(7, 'a', 2, 'prepare');
const first = publish([prepare, query(8, 'b', 1)]);
state.valid = false;
const later = publish([prepare, query(8, 'b', 1)]);
const competing = publish([prepare, row(8, 'b', 2, 'prepare')]);
process.stdout.write(JSON.stringify({first, later, competing}));
""")
        decided = out["first"]["packets"][0]["completion"]
        token = out["first"]["packets"][0]["preparation"]["token"]
        self.assertTrue(token)
        self.assertEqual(decided, {"request": 2, "intent": "prepare", "accepted": True,
                                   "token": token, "reason": ""})
        self.assertIsNone(out["first"]["packets"][1]["completion"])
        # Validity is re-checked in the preparation; the completion does not follow it.
        later = out["later"]["packets"][0]
        self.assertFalse(later["preparation"]["ready"])
        self.assertEqual(later["completion"], decided)
        # A frame caused by another consumer's request keeps it too.
        holder, competitor = out["competing"]["packets"]
        self.assertEqual(holder["completion"], decided)
        self.assertEqual(competitor["completion"], refused(2, "busy"))

    def test_a_refusal_keeps_the_reason_it_was_first_given(self):
        for cause, setup, reason in (("stale view", "state.generation = 5;", "stale-context"),
                                     ("popup focus", "state.focus = false;",
                                      "popup-focus-unconfirmed")):
            with self.subTest(cause=cause):
                out = self.run_publication(setup + """
const prepare = row(7, 'a', 2, 'prepare');
const first = publish([prepare]);
state.generation = 0; state.focus = true;
const later = publish([prepare]);
process.stdout.write(JSON.stringify({first, later}));
""")
                self.assertEqual(out["first"]["packets"][0]["completion"], refused(2, reason))
                self.assertFalse(out["later"]["packets"][0]["preparation"]["ready"])
                self.assertEqual(out["later"]["packets"][0]["completion"], refused(2, reason))

    def test_the_completion_survives_frames_while_the_target_context_is_unavailable(self):
        out = self.run_publication("""
const prepare = row(7, 'a', 2, 'prepare');
const first = publish([prepare]);
state.ready = false;
const later = publish([prepare]);
process.stdout.write(JSON.stringify({first, later}));
""")
        later = out["later"]["packets"][0]
        self.assertEqual(later["preparation"]["reason"], "unavailable")
        self.assertTrue(later["completion"]["accepted"])
        self.assertEqual(later["completion"], out["first"]["packets"][0]["completion"])

    def test_an_undecided_request_carries_no_completion_until_it_is_decided(self):
        out = self.run_publication("""
state.ready = false;
const prepare = row(7, 'a', 2, 'prepare');
const waiting = publish([prepare]);
state.ready = true;
const decided = publish([prepare]);
process.stdout.write(JSON.stringify({waiting, decided}));
""")
        self.assertEqual(out["waiting"]["packets"][0]["preparation"]["reason"], "unavailable")
        self.assertIsNone(out["waiting"]["packets"][0]["completion"])
        self.assertTrue(out["decided"]["packets"][0]["completion"]["accepted"])

    def test_rows_that_are_not_the_consumers_decided_request_carry_no_completion(self):
        out = self.run_publication("""
const decided = publish([row(7, 'a', 3, 'prepare')]);
const rows = publish([
    query(8, 'b', 1),
    row(7, 'a', 2, 'prepare'),
    row(7, 'a', 3, 'prepare', {consumerLease: lease.b}),
    row(8, 'b', 2, 'prepare', {version: 2})
]);
process.stdout.write(JSON.stringify({decided, rows}));
""")
        self.assertTrue(out["decided"]["packets"][0]["completion"]["accepted"])
        # A query, an older request, another consumer's lease and a malformed request.
        self.assertEqual([packet["completion"] for packet in out["rows"]["packets"]],
                         [None, None, None, None])

    def test_a_new_request_ends_the_previous_completion(self):
        out = self.run_publication("""
const first = publish([row(7, 'a', 2, 'prepare')]);
const token = first.packets[0].completion.token;
const validated = publish([row(7, 'a', 3, 'validate', {token})]);
const queried = publish([query(7, 'a', 4)]);
const again = publish([row(7, 'a', 5, 'prepare')]);
process.stdout.write(JSON.stringify({first, validated, queried, again}));
""")
        self.assertTrue(out["validated"]["packets"][0]["preparation"]["ready"])
        self.assertIsNone(out["validated"]["packets"][0]["completion"])
        self.assertIsNone(out["queried"]["packets"][0]["completion"])
        renewed = out["again"]["packets"][0]["completion"]
        self.assertEqual((renewed["request"], renewed["accepted"]), (5, True))
        self.assertNotEqual(renewed["token"], out["first"]["packets"][0]["completion"]["token"])

    def test_every_frame_at_the_decided_number_carries_the_completion(self):
        # The completion belongs to the consumer's identity, lease and request number: a
        # conflicting or malformed row at that number still repeats it, whatever its own answer.
        out = self.run_publication("""
const first = publish([row(7, 'a', 2, 'prepare')]);
const rows = publish([row(7, 'a', 2, 'prepare', {outputName: 'Virtual-1'})]);
const malformed = publish([row(7, 'a', 2, 'prepare', {version: 2})]);
process.stdout.write(JSON.stringify({first, rows, malformed}));
""")
        decided = out["first"]["packets"][0]["completion"]
        conflicting = out["rows"]["packets"][0]
        self.assertEqual(conflicting["preparation"]["reason"], "stale-or-conflicting-request")
        self.assertEqual(conflicting["completion"], decided)
        malformed = out["malformed"]["packets"][0]
        self.assertEqual((malformed["preparation"]["intent"], malformed["preparation"]["reason"]),
                         ("invalid", "malformed"))
        self.assertEqual(malformed["completion"], decided)

    def test_an_advanced_request_does_not_revive_the_previous_completion(self):
        out = self.run_publication("""
const prepare = row(7, 'a', 2, 'prepare');
const first = publish([prepare]);
publish([row(7, 'a', 3, 'validate', {token: first.packets[0].completion.token})]);
const replayed = publish([prepare]);
process.stdout.write(JSON.stringify({replayed}));
""")
        replayed = out["replayed"]["packets"][0]
        self.assertEqual(replayed["preparation"]["reason"], "stale-or-conflicting-request")
        self.assertIsNone(replayed["completion"])

    def test_a_replaced_consumer_cannot_inherit_a_completion(self):
        out = self.run_publication("""
const old = row(7, 'a', 2, 'prepare');
const decided = publish([old]);
probe.reconcileTargetConsumers({complete: true, widgets: [{id: 8, consumer: 'b'}]});
probe.reconcileTargetConsumers({complete: true,
                                widgets: [{id: 7, consumer: 'a'}, {id: 8, consumer: 'b'}]});
const returned = publish([old]);
process.stdout.write(JSON.stringify({
    decided, returned, renewed: probe.targetConsumerFor(7, 'a').lease !== old.consumerLease
}));
""")
        self.assertTrue(out["decided"]["packets"][0]["completion"]["accepted"])
        self.assertTrue(out["renewed"])
        returned = out["returned"]["packets"][0]
        self.assertEqual(returned["preparation"]["reason"], "consumer-not-current")
        self.assertIsNone(returned["completion"])

    def test_offline_frames_carry_no_completion(self):
        out = self.run_publication("""
const prepare = row(7, 'a', 2, 'prepare');
publish([prepare]);
const offline = publish([prepare], 'offline');
process.stdout.write(JSON.stringify({offline}));
""")
        self.assertIsNone(out["offline"]["packets"][0]["preparation"])
        self.assertIsNone(out["offline"]["packets"][0]["completion"])

    def test_the_native_target_line_records_the_published_completion(self):
        out = self.run_publication("""
const prepare = row(7, 'a', 2, 'prepare');
publish([prepare, query(8, 'b', 1)]);
state.valid = false;
publish([prepare, row(8, 'b', 2, 'prepare')]);
process.stdout.write(JSON.stringify(frames));
""")
        for frame in out:
            targets = [packet for packet in frame["packets"] if packet["preparation"] is not None]
            self.assertEqual(len(frame["lines"]), len(targets))
            for line, packet in zip(frame["lines"], targets, strict=True):
                self.assertEqual((line["consumer"], line["request"], line["revision"]),
                                 (packet["consumer"], packet["request"], packet["revision"]))
                self.assertEqual(line["completion"], packet["completion"])


class CompletionSeedTests(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory(prefix="pf-completion-seed-", dir="/tmp/opencode")
        self.addCleanup(scratch.cleanup)
        self.root = Path(scratch.name)
        self.stage = self.root / "build/stage"
        rules = (self.stage
                 / ".local/share/kwin/scripts/plasmafusion-placement/contents/ui/Tiling.js")
        rules.parent.mkdir(parents=True)
        rules.write_text("// private staged rules\n")
        self.output = self.root / "build/seed"

    def run_seed(self, *arguments, stage=True):
        options = ["--stage", str(self.stage), "--output", str(self.output)] if stage else []
        return subprocess.run(
            [sys.executable, str(PREPARER), *options, *arguments],
            cwd=self.root, capture_output=True, text=True, timeout=10, check=False,
        )

    def test_completion_seed_is_a_target_case_with_its_checker_and_scenario(self):
        result = self.run_seed("--completion-probe")
        self.assertEqual(result.returncode, 0, result.stderr)
        config = (self.output / ".config/kwinrc").read_text()
        for setting in ("CompletionProbe=true", "TargetProbe=true", "FocusProbe=true",
                        "MixedLifetimeProbe=false", "ViewLossProbe=false", "PipelineProbe=false",
                        "RefusedBackendProbe=false", "DropRetirementFrame=false",
                        "ReplyDelayMs=0"):
            self.assertIn(setting, config)
        manifest = json.loads((self.output / "probe-inputs.json").read_text())
        for name in ("completion.py", "completion_scenario.sh", "mixed_lifetime.py",
                     "receipts.py", "cleanup.py"):
            copied = (self.output / ".local/lib/layout-control" / name).read_bytes()
            self.assertEqual(copied, (HERE / name).read_bytes())
            self.assertEqual(manifest[name], hashlib.sha256(copied).hexdigest())

    def test_other_seeds_keep_the_completion_case_off(self):
        for flags in ((), ("--target-probe",), ("--view-loss-probe",)):
            with self.subTest(flags=flags):
                result = self.run_seed(*flags)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("CompletionProbe=false",
                              (self.output / ".config/kwinrc").read_text())
                manifest = json.loads((self.output / "probe-inputs.json").read_text())
                for name in ("completion.py", "completion_scenario.sh"):
                    self.assertNotIn(name, manifest)
                # The preparer refuses an existing output, so each seed gets a fresh one.
                shutil.rmtree(self.output)

    def test_completion_case_is_separate_from_the_other_private_cases(self):
        for extra in (("--mixed-lifetime-probe",), ("--view-loss-probe",),
                      ("--refused-backend-probe",), ("--pipeline-probe",),
                      ("--drop-retirement-frame",),
                      ("--query-timeout-ms", "200", "--reply-delay-ms", "2000")):
            with self.subTest(extra=extra):
                result = self.run_seed("--completion-probe", *extra)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("completion case", result.stderr)
                self.assertFalse(self.output.exists())

    def test_completion_seed_preparation_is_not_a_result_check(self):
        result = self.run_seed("--check-result", str(self.root), "--completion-probe",
                               stage=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("cannot be combined", result.stderr)


class CompletionScenarioTests(unittest.TestCase):
    def test_bridge_branches_after_the_first_accepted_preparation(self):
        bridge = (HERE / "scenario-bridge.sh").read_text()
        prepared = bridge.index('target_prepare_request=$(wait_target_reply "$focus_boot" '
                                'prepare true 1 pf.focus.alpha)')
        branch = bridge.index("--key CompletionProbe")
        sourced = bridge.index('source "$HOME/.local/lib/layout-control/completion_scenario.sh"')
        validate = bridge.index('pfinput "key space"', prepared)
        self.assertLess(prepared, branch)
        self.assertLess(branch, sourced)
        self.assertLess(sourced, validate)
        # The case ends the session itself, after quitting the client it started.
        cursor = sourced
        for item in ("printf 'quit\\n' >&\"$focus_input\"", 'wait "$focus_client"',
                     "finish_probe_session", "return 0"):
            cursor = bridge.index(item, cursor)
        self.assertLess(cursor, validate)

    def test_each_step_is_marked_before_the_action_it_checks(self):
        scenario = (HERE / "completion_scenario.sh").read_text()
        order = ["completion_subject holder", "completion_wait accepted",
                 "completion_mark context", 'pfinput "key esc"', "completion_wait context",
                 "completion_subject competitor", 'pfinput "click $alpha_x $alpha_y"',
                 'pfinput "click $competitor_x $competitor_y"', "completion_mark competitor",
                 'pfinput "key space"', "completion_wait competitor",
                 "completion_mark refusal", 'pfinput "key esc"', "completion_wait refusal",
                 'pfinput "click $focus_x $focus_y"', "VirtualDesktopManager.createDesktop",
                 "completion_popup_kept", "completion_mark stale", 'pfinput "key space"',
                 "completion_wait stale", "completion_mark stale-kept", 'pfinput "key esc"',
                 "completion_wait stale-kept", '"$completion_helper" receipt "$OUT"']
        cursor = 0
        for item in order:
            cursor = scenario.index(item, cursor)
        self.assertRegex(scenario, re.compile(r"^set -euo pipefail$", re.M))
        for forbidden in ("kwriteconfig", "reconfigure", "systemctl", "ssh ", "sudo", "podman",
                          "removeDesktop", "setCurrentDesktop"):
            self.assertNotIn(forbidden, scenario)
        guard = scenario[:scenario.index("completion_mark()")]
        for requirement in ("/var/tmp/pfv-layout-control-*", "PF_LAYOUT_PRIVATE_CONTAINER",
                            "/run/.containerenv"):
            self.assertIn(requirement, guard)

    def test_the_desktop_change_must_leave_the_holders_popup_active(self):
        scenario = (HERE / "completion_scenario.sh").read_text()
        check = scenario.split("completion_popup_kept() {", 1)[1].split("\n}\n", 1)[0]
        for requirement in ('"context-changed"', '"activeAppletPopup"', '"activePid"',
                            "focus-shell-pid.txt"):
            self.assertIn(requirement, check)


HOLDER, COMPETITOR = "1795000000001:0.11", "1795000000002:0.22"
EPOCH = "c" * 32
TOKEN = EPOCH + ":1"
ACCEPTED = {"request": 2, "intent": "prepare", "accepted": True, "token": TOKEN, "reason": ""}
BUSY = refused(2, "busy")
STALE = refused(3, "stale-context")
MISSING = object()


def prepare(boot, request, *, completion, ready=False, reason="stale-context", token="",
            native=MISSING):
    frame = {"boot": boot, "request": request, "intent": "prepare", "ready": ready,
             "reason": "" if ready else reason, "token": token if ready else "",
             "completion": completion}
    if native is not MISSING:
        frame["native"] = native
    return frame


def query(boot, request):
    return {"boot": boot, "request": request, "intent": "query", "ready": False, "reason": "",
            "token": "", "completion": None}


class CompletionRun:
    """Synthetic raw evidence in the order the native scenario produces it."""

    def __init__(self, root: Path):
        self.root, self.kwin, self.shell = root, ["qml: layout-probe: initialized true -1\n"], []
        self.revision = self.generation = 0

    def flush(self) -> None:
        (self.root / "kwin.log").write_text("".join(self.kwin))
        (self.root / "plasmashell.log").write_text("".join(self.shell))

    def context(self) -> None:
        self.generation += 1
        self.kwin.append("qml: layout-probe-focus " + json.dumps({
            "event": "context-changed", "contextGeneration": self.generation,
            "activeAppletPopup": False}) + "\n")

    def publish(self, *frames, epoch=EPOCH, malformed=False) -> None:
        """One publication: a native verdict per target row, then each consumer's reception."""
        published = []
        for frame in frames:
            self.revision += 1
            published.append((self.revision, frame))
            if frame["intent"] == "query":
                continue
            native = {"consumer": frame["boot"], "request": frame["request"],
                      "intent": frame["intent"], "revision": self.revision,
                      "ready": frame["ready"], "reason": frame["reason"],
                      "targetClass": frame.get("class", "pf.focus.alpha") if frame["ready"] else "",
                      "targetAlive": frame["ready"],
                      "completion": frame.get("native", frame["completion"])}
            if malformed:
                del native["completion"]
            self.kwin.append("qml: layout-probe-target " + json.dumps(native) + "\n")
        self.kwin.append(f"qml: layout-probe: publication online {len(frames)}\n")
        self.kwin.append(f"qml: layout-probe: publication writes {len(frames)}\n")
        for revision, frame in published:
            if frame.get("missed"):
                # Published, but the consumer never received it.
                continue
            preparation = None if frame["intent"] == "query" else {
                "intent": frame["intent"], "ready": frame["ready"], "reason": frame["reason"],
                "token": frame["token"]} | frame.get("received", {})
            packet = {"consumer": frame["boot"], "epoch": epoch, "revision": revision,
                      "status": "online", "capable": True, "refusal": -1,
                      "request": frame["request"], "preparation": preparation,
                      "completion": frame["completion"], "targetContext": frame.get("context"),
                      "competingProviderRejected": True, "backendOwner": ":1.0",
                      "identityName": "org.plasmafusion.LayoutProbe.p" + epoch}
            self.shell.append("qml: layout-probe-received "
                              + json.dumps(packet | {"receiverBoot": frame["boot"]}) + "\n")
            self.shell.append("qml: layout-probe-observation " + json.dumps({
                "boot": frame["boot"], "phase": "online", "epoch": epoch, "revision": revision,
                "accepted": revision, "packet": packet, "request": frame["request"]}) + "\n")

    def subject(self, role: str, boot: str) -> None:
        (self.root / f"completion-subject-{role}.json").write_text(json.dumps({"schema": 1,
                                                                               "boot": boot}))

    def mark(self, label: str) -> None:
        self.flush()
        checker().mark(self.root, label)

    def step(self, name: str) -> dict:
        self.flush()
        return checker().record_step(self.root, name)

    def build(self, *, drift=False, dropped=False, mismatch=False, consumer_mismatch=False,
              no_context=False, still_valid=False, competitor_alone=False,
              competitor_accepted=False, refusal_lost=False, stale_accepted=False,
              validate_completion=False, two_lifetimes=False, malformed=False,
              refusal_token=False, holder_refused=False, conflict=False, early_decision=False,
              re_leased=False, missed_delivery=False, second_start=False,
              advanced_drop=False, advanced_change=False, received_mismatch=False,
              early_newer=False) -> None:
        held = prepare(HOLDER, 2, completion=ACCEPTED)
        busy = prepare(COMPETITOR, 2, completion=BUSY, reason="busy")
        # The holder's preparation was accepted before the case began.
        self.subject("holder", HOLDER)
        decided = (ACCEPTED | {"accepted": False}) if mismatch else ACCEPTED
        first = prepare(HOLDER, 2, ready=True, token=TOKEN, completion=decided)
        if holder_refused:
            first = prepare(HOLDER, 2, reason="popup-focus-unconfirmed",
                            completion=refused(2, "popup-focus-unconfirmed"))
        other = query(COMPETITOR, 1)
        if validate_completion:
            other = dict(other, intent="validate", completion=BUSY)
        if early_decision:
            # An answer given before the request is handled cannot decide it.
            other = prepare(COMPETITOR, 1, reason="stale-or-conflicting-request",
                            completion=refused(1, "stale-or-conflicting-request"))
        self.publish(first, other, malformed=malformed)
        self.step("accepted")
        if second_start:
            self.kwin.append("qml: layout-probe: initialized true -1\n")
        self.mark("context")
        if not no_context:
            self.context()
        later = held
        if drift:
            later = prepare(HOLDER, 2, completion=refused(2, "stale-context"))
        elif dropped:
            later = prepare(HOLDER, 2, completion=None)
        elif re_leased:
            # Stricter than the provider: a re-leased consumer at its decided request fails.
            later = prepare(HOLDER, 2, reason="consumer-not-current", completion=None)
        elif still_valid:
            later = prepare(HOLDER, 2, ready=True, token=TOKEN, completion=ACCEPTED)
        elif consumer_mismatch:
            # The native verdict keeps the decision; the received frame does not.
            later = prepare(HOLDER, 2, completion=ACCEPTED | {"token": "x"}, native=ACCEPTED)
        elif received_mismatch:
            # The verdict reports the target no longer valid; the received frame says ready.
            later = dict(held, received={"ready": True, "reason": "", "token": TOKEN})
        self.publish(later, query(COMPETITOR, 1), epoch="d" * 32 if two_lifetimes else EPOCH)
        self.step("context")
        # The competitor's menu opens from the controlled app: two more context changes.
        self.subject("competitor", COMPETITOR)
        for opening in range(2):
            self.context()
            frame = held
            if conflict and opening == 0:
                # A conflicting row at the decided number repeats the decided completion.
                frame = dict(prepare(HOLDER, 2, reason="stale-or-conflicting-request",
                                     completion=ACCEPTED), intent="validate")
            if early_newer:
                # A newer request answered only early leaves the record, and so the completion,
                # at the decided request: an older row that then drops it is a fault.
                frame = (prepare(HOLDER, 3, reason="unavailable", completion=None) if opening == 0
                         else prepare(HOLDER, 2, completion=None))
            self.publish(frame, query(COMPETITOR, 1))
        self.mark("competitor")
        decision = busy
        if refusal_token:
            decision = prepare(COMPETITOR, 2, completion=BUSY | {"token": "x"}, reason="busy")
        if competitor_accepted:
            decision = prepare(COMPETITOR, 2, ready=True, token=EPOCH + ":2",
                               completion=ACCEPTED | {"token": EPOCH + ":2"})
        if competitor_alone:
            self.publish(decision)
        else:
            self.publish(held, decision)
        self.step("competitor")
        self.mark("refusal")
        if missed_delivery:
            # A frame published before the context change cannot stand for one published after it.
            self.publish(held, busy)
        self.context()
        if refusal_lost:
            self.publish(held)
        else:
            self.publish(held, dict(busy, missed=True) if missed_delivery else busy)
        self.step("refusal")
        # The holder's menu opens from the app, then a desktop is created while it stays open.
        for _ in range(3):
            self.context()
            self.publish(held, busy)
        self.mark("stale")
        stale = (prepare(HOLDER, 3, ready=True, token=EPOCH + ":3",
                         completion=ACCEPTED | {"request": 3, "token": EPOCH + ":3"})
                 if stale_accepted else prepare(HOLDER, 3, completion=STALE))
        self.publish(stale, busy)
        self.step("stale")
        if advanced_drop or advanced_change:
            # The holder's request has advanced: an older row may drop the old completion, but a
            # completion it carries must still be the decided one.
            self.publish(prepare(HOLDER, 2, reason="stale-or-conflicting-request",
                                 completion=refused(2, "changed") if advanced_change else None),
                         busy)
        self.mark("stale-kept")
        self.context()
        self.publish(prepare(HOLDER, 3, completion=STALE, reason="refused"), busy)
        self.step("stale-kept")


class CompletionCheckerTests(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory(prefix="pf-completion-check-", dir="/tmp/opencode")
        self.addCleanup(scratch.cleanup)
        self.root = Path(scratch.name)
        write_cleanup_fixture(self.root)
        self.run_ = CompletionRun(self.root)

    def assert_rejected(self, message: str, **variant) -> None:
        with self.assertRaisesRegex(ValueError, message):
            self.run_.build(**variant)
            checker().write_receipt(self.root)
        self.assertFalse((self.root / "completion-result.json").exists())

    def test_kept_completions_pass_and_record_each_decision(self):
        self.run_.build()
        checker().write_receipt(self.root)
        receipt = json.loads((self.root / "completion-result.json").read_text())
        self.assertEqual(receipt, {"schema": 1, "passed": True, "checks": checker().CHECKS})
        accepted = json.loads((self.root / "completion-accepted.json").read_text())
        self.assertEqual(accepted["holder"], {"request": 2, "revision": 1, "completion": ACCEPTED})
        competitor = json.loads((self.root / "completion-competitor.json").read_text())
        self.assertEqual(competitor["competitor"]["completion"], BUSY)
        stale = json.loads((self.root / "completion-stale.json").read_text())
        self.assertEqual(stale["holder"]["completion"], STALE)
        with self.assertRaises(OSError):
            checker().write_receipt(self.root)

    def test_a_completion_recomputed_from_a_newer_frame_fails(self):
        # What the previous probe offered: the latest frame's answer, re-decided every scan.
        self.assert_rejected("changed after its decision", drift=True)

    def test_a_newer_frame_that_drops_the_completion_fails(self):
        self.assert_rejected("dropped a decided completion", dropped=True)

    def test_a_completion_that_differs_from_its_deciding_answer_fails(self):
        self.assert_rejected("does not match the answer that decided it", mismatch=True)

    def test_a_refusal_that_carries_a_handle_fails(self):
        self.assert_rejected("does not match the answer that decided it", refusal_token=True)

    def test_the_holders_first_decided_preparation_must_be_accepted(self):
        self.assert_rejected("first preparation was not accepted", holder_refused=True)

    def test_a_received_completion_that_differs_from_the_native_verdict_fails(self):
        self.assert_rejected("differs from the provider's", consumer_mismatch=True)

    def test_a_received_preparation_that_differs_from_the_native_verdict_fails(self):
        self.assert_rejected("does not match its native verdict", received_mismatch=True)

    def test_a_frame_without_a_context_change_cannot_stand_for_one(self):
        self.assert_rejected("no context change", no_context=True)

    def test_validity_must_be_reported_separately(self):
        self.assert_rejected("validity", still_valid=True)

    def test_the_competitors_decision_must_also_carry_the_holders_completion(self):
        self.assert_rejected("holder's completion", competitor_alone=True)

    def test_the_competitor_must_be_refused_as_busy(self):
        self.assert_rejected("busy", competitor_accepted=True)

    def test_a_refusal_must_be_kept_by_a_newer_frame(self):
        self.assert_rejected("no newer frame", refusal_lost=True)

    def test_the_stale_preparation_must_be_refused_for_its_stale_context(self):
        self.assert_rejected("stale-context", stale_accepted=True)

    def test_a_validation_frame_carrying_a_completion_fails(self):
        self.assert_rejected("validate frame carried a completion", validate_completion=True)

    def test_frames_from_another_provider_lifetime_fail(self):
        self.assert_rejected("one provider lifetime", two_lifetimes=True)

    def test_a_native_verdict_without_its_completion_field_fails(self):
        self.assert_rejected("malformed native target verdict", malformed=True)

    def test_a_conflicting_row_at_the_decided_number_may_repeat_the_completion(self):
        self.run_.build(conflict=True)
        checker().write_receipt(self.root)
        self.assertTrue((self.root / "completion-result.json").is_file())

    def test_an_answer_that_cannot_decide_a_request_must_not_carry_a_completion(self):
        self.assert_rejected("cannot decide", early_decision=True)

    def test_a_re_leased_consumer_at_its_decided_request_fails(self):
        # Stricter than the provider, which drops the completion for an unknown lease.
        self.assert_rejected("dropped a decided completion", re_leased=True)

    def test_an_advanced_request_may_drop_its_old_completion(self):
        self.run_.build(advanced_drop=True)
        checker().write_receipt(self.root)
        self.assertTrue((self.root / "completion-result.json").is_file())

    def test_an_advanced_request_cannot_change_its_old_completion(self):
        self.assert_rejected("changed after its decision", advanced_change=True)

    def test_an_early_answer_to_a_newer_request_does_not_supersede_the_decision(self):
        self.assert_rejected("dropped a decided completion", early_newer=True)

    def newer_than_the_decision(self, newer: dict) -> dict:
        """The holder's decided request 2, a newer request 3, then a row for request 2 that drops
        its completion, as the provider does once it has handled the newer request."""
        def verdict(index, request, *, intent="prepare", ready=False, reason="stale-context",
                    completion=None):
            return (index, {"consumer": HOLDER, "request": request, "intent": intent,
                            "revision": index + 1, "ready": ready, "reason": reason,
                            "targetClass": "pf.focus.alpha" if ready else "",
                            "targetAlive": ready, "completion": completion})
        return checker().decisions([
            verdict(0, 2, ready=True, reason="", completion=ACCEPTED),
            verdict(1, 3, **newer),
            verdict(2, 2, reason="stale-or-conflicting-request"),
        ])

    def test_a_handled_newer_answer_supersedes_the_decision_by_itself(self):
        # A validation's handled answer advances without a completion; a refusal at handle
        # exhaustion advances through its completion although its answer reads as a wait.
        for name, newer in (("validation", {"intent": "validate", "reason": "focus-changed"}),
                            ("exhausted", {"reason": "unavailable",
                                           "completion": refused(3, "unavailable")})):
            with self.subTest(newer=name):
                decided = self.newer_than_the_decision(newer)
                self.assertEqual(sorted(decided), [(HOLDER, 2), (HOLDER, 3)]
                                 if name == "exhausted" else [(HOLDER, 2)])

    def test_a_newer_validation_answered_unavailable_does_not_supersede_the_decision(self):
        # Stricter than the provider, which may have handled it after handle exhaustion. The
        # checker keeps this because an early unavailable answer to a validation produces the
        # same verdict, and that one leaves the record, and its completion, at the older request.
        with self.assertRaisesRegex(ValueError, "dropped a decided completion"):
            self.newer_than_the_decision({"intent": "validate", "reason": "unavailable"})

    def test_delivery_must_come_from_a_frame_published_after_the_context_change(self):
        self.assert_rejected("no newer frame accepted by", missed_delivery=True)

    def test_a_second_provider_start_fails(self):
        self.assert_rejected("one provider lifetime", second_start=True)

    def test_marks_and_step_records_are_written_once(self):
        self.run_.build()
        with self.assertRaises(FileExistsError):
            checker().mark(self.root, "context")
        with self.assertRaises(FileExistsError):
            checker().record_step(self.root, "stale-kept")

    def test_a_tampered_record_fails_recomputation(self):
        self.run_.build()
        record = self.root / "completion-context.json"
        value = json.loads(record.read_text())
        value["revision"] += 1
        record.write_text(json.dumps(value))
        with self.assertRaisesRegex(ValueError, "does not match its raw evidence"):
            checker().write_receipt(self.root)

    def test_the_receipt_requires_every_step(self):
        self.run_.build()
        (self.root / "completion-stale-kept.json").unlink()
        with self.assertRaises(OSError):
            checker().write_receipt(self.root)
        self.assertFalse((self.root / "completion-result.json").exists())

    def test_check_result_requires_the_receipt_and_rechecks_the_evidence(self):
        self.run_.build()
        (self.root / "scenario.log").write_text("scenario rc=0\nsession rc=0\n")
        check = [sys.executable, str(PREPARER), "--check-result", str(self.root),
                 "--scope", "completion"]
        missing = subprocess.run(check, capture_output=True, text=True, timeout=10, check=False)
        self.assertNotEqual(missing.returncode, 0)
        self.assertIn("missing probe receipt", missing.stderr)
        checker().write_receipt(self.root)
        passed = subprocess.run(check, capture_output=True, text=True, timeout=10, check=False)
        self.assertEqual(passed.returncode, 0, passed.stderr)
        record = self.root / "completion-refusal.json"
        value = json.loads(record.read_text())
        value["revision"] = 0
        record.write_text(json.dumps(value))
        tampered = subprocess.run(check, capture_output=True, text=True, timeout=10, check=False)
        self.assertNotEqual(tampered.returncode, 0)
        self.assertIn("does not match its raw evidence", tampered.stderr)


if __name__ == "__main__":
    unittest.main()
