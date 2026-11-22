# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Bounded, serialized read/publish pipeline cases, re-exported by the existing entry point."""

import hashlib
import importlib
import json
import re
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
PROVIDER = HERE / "provider.qml"
PREPARER = HERE / "prepare_seed.py"


def checker():
    """Import lazily: a missing checker fails these cases, not the whole entry point."""
    name = f"{__package__}.pipeline" if __package__ else "pipeline"
    return importlib.import_module(name)


def closing(source: str, opening: int) -> int:
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return end


def signal_handler(anchor: str, signal: str, parameter: str = "value") -> str:
    """The provider's QML handler for `signal` after `anchor`, as a JavaScript function."""
    source = PROVIDER.read_text()
    at = source.index(f"{signal}: ", source.index(anchor)) + len(signal) + 2
    rest = source[at:]
    arrow = f"{parameter} => "
    if rest.startswith(arrow + "{") or rest.startswith("{"):
        opening = source.index("{", at)
        return f"(({parameter}) => {source[opening:closing(source, opening)]})"
    line = rest.split("\n", 1)[0]
    expression = line[len(arrow):] if line.startswith(arrow) else line
    return f"(({parameter}) => {{ {expression}; }})"


FUNCTIONS = ("scan", "finishRead", "publicationFinished", "releaseDuePublication",
             "queuePublication", "cancelPublication", "publish", "readMailboxes")
HARNESS = r"""
const calls = [], logs = [], deferred = [], timers = [];
console.info = (...args) => logs.push(args.map(String).join(' '));
console.warn = console.info;
const Qt = {callLater: callback => deferred.push(callback)};
const probe = {
    authorized: true, stopping: false, identityReady: true, reading: false, again: false,
    publishing: false, publicationDue: false, targetProbe: false, mixedLifetimeProbe: false,
    replyDelayMs: DELAY, pendingPublication: null, recipients: [], readOwner: '', replyOwner: '',
    revision: 0, epoch: 'e'.repeat(32), capable: true, refusal: -1,
    competingProviderRejected: true, selfOwner: ':1.0', identityName: 'alias'
};
const ownerLookup = {call: () => calls.push('owner')};
const reader = {arguments: [], call: () => calls.push('read')};
const writer = {arguments: [], service: '', call: () => calls.push('publish')};
const publicationFactory = {createObject: (parent, props) => {
    const timer = Object.assign({running: false, destroyed: false}, props);
    timer.start = () => { timer.running = true; };
    timer.stop = () => { timer.running = false; };
    timer.destroy = () => { timer.destroyed = true; };
    timers.push(timer);
    return timer;
}};
const methods = (function(){with(probe){return {FUNCTIONS};}})();
Object.assign(probe, methods);
const ownerFinished = OWNER_FINISHED;
const readerFinished = READER_FINISHED;
const writerFinished = WRITER_FINISHED;
const writerFailed = WRITER_FAILED;
const timerTriggered = TIMER_TRIGGERED;
const drain = () => { while (deferred.length) deferred.shift()(); };
const rows = [{id: 1, consumer: 'a', request: 1}, {id: 2, consumer: 'b', request: 1}];
const read = (found = rows) => {
    ownerFinished([':1.5']);
    readerFinished([JSON.stringify(found)]);
};
const count = name => calls.filter(call => call === name).length;
const emit = value => process.stdout.write(JSON.stringify(value));
"""


class PipelineSerializationTests(unittest.TestCase):
    """Run the provider's actual pipeline functions and D-Bus handlers in order."""

    def run_pipeline(self, action: str, *, delay: int = 0) -> dict:
        functions = ",".join(f"{name}:{qml_handler(name, 'provider.qml')}" for name in FUNCTIONS)
        script = (HARNESS.replace("DELAY", str(delay)).replace("FUNCTIONS", functions)
                  .replace("OWNER_FINISHED", signal_handler("id: ownerLookup\n", "onFinished"))
                  .replace("READER_FINISHED", signal_handler("id: reader\n", "onFinished"))
                  .replace("WRITER_FINISHED", signal_handler("id: writer\n", "onFinished"))
                  .replace("WRITER_FAILED", signal_handler("id: writer\n", "onFailed", ""))
                  .replace("TIMER_TRIGGERED", signal_handler("id: delayed\n", "onTriggered",
                                                             "delayed")))
        result = subprocess.run(["node", "-"], input=script + action, capture_output=True,
                                text=True, timeout=10, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_no_read_starts_while_a_publication_is_outstanding(self):
        out = self.run_pipeline("""
probe.scan(); read();
const published = calls.slice();
probe.scan(); drain();
const during = calls.slice();
writerFinished(['2']); drain();
emit({published, during, after: calls, publishing: probe.publishing, again: probe.again});
""")
        self.assertEqual(out["published"], ["owner", "read", "publish"])
        self.assertEqual(out["during"], out["published"], "a read started during a publication")
        self.assertEqual(out["after"], ["owner", "read", "publish", "owner"])
        self.assertEqual((out["publishing"], out["again"]), (False, False))

    def test_wakes_during_a_publication_coalesce_into_one_read(self):
        out = self.run_pipeline("""
probe.scan(); read();
for (let wake = 0; wake < 5; ++wake) probe.scan();
drain();
writerFinished(['2']); drain();
emit({owners: count('owner'), reads: count('read'), publications: count('publish')});
""")
        self.assertEqual(out, {"owners": 2, "reads": 1, "publications": 1})

    def test_failed_publication_also_resumes_the_pipeline(self):
        out = self.run_pipeline("""
probe.scan(); read();
probe.scan(); drain();
writerFailed(); drain();
emit({owners: count('owner'), publishing: probe.publishing});
""")
        self.assertEqual(out, {"owners": 2, "publishing": False})

    def test_publication_is_outstanding_only_when_it_was_sent(self):
        out = self.run_pipeline("""
probe.scan(); read([]);
const empty = probe.publishing;
probe.publish('online', rows, 'not-a-unique-name');
emit({empty, invalid: probe.publishing, publications: count('publish'),
      reading: probe.reading});
""")
        self.assertEqual(out, {"empty": False, "invalid": False, "publications": 0,
                               "reading": False})

    def test_delayed_publication_waits_for_a_running_read(self):
        out = self.run_pipeline("""
probe.scan(); read();
probe.scan(); drain();
const queued = timers.length;
timerTriggered(timers[0]);
const whileReading = count('publish');
read();
const afterRead = count('publish');
emit({queued, whileReading, afterRead, destroyed: timers[0].destroyed,
      released: logs.filter(line => line.includes('delayed publication released')).length});
""", delay=2000)
        self.assertEqual(out, {"queued": 1, "whileReading": 0, "afterRead": 1, "destroyed": True,
                               "released": 1})

    def test_delayed_publication_released_at_once_when_idle(self):
        out = self.run_pipeline("""
probe.scan(); read();
timerTriggered(timers[0]);
emit({publications: count('publish'), publishing: probe.publishing,
      pending: probe.pendingPublication !== null});
""", delay=2000)
        self.assertEqual(out, {"publications": 1, "publishing": True, "pending": False})

    def test_cancelled_publication_clears_its_due_release(self):
        out = self.run_pipeline("""
probe.scan(); read();
probe.scan(); drain();
timerTriggered(timers[0]);
ownerFinished([':1.9']);
readerFinished([JSON.stringify(rows)]);
emit({publications: count('publish'), timers: timers.length, due: probe.publicationDue,
      firstDestroyed: timers[0].destroyed, secondRunning: timers[1].running});
""", delay=2000)
        self.assertEqual(out, {"publications": 0, "timers": 2, "due": False,
                               "firstDestroyed": True, "secondRunning": True})

    def test_pipeline_progress_is_logged_for_the_native_checker(self):
        out = self.run_pipeline("""
probe.scan(); read(); writerFinished(['2']); drain();
emit(logs.filter(line => /read (started|finished)|publication (online|writes)/.test(line)));
""")
        self.assertEqual(out[:4], ["layout-probe: read started",
                                   "layout-probe: publication online 2",
                                   "layout-probe: read finished",
                                   "layout-probe: publication writes 2"])

    def run_target_lookup(self, action: str) -> dict:
        """The pipeline with target mode's shell PID lookup and its context handlers."""
        names = FUNCTIONS + ("targetViewChanged", "advanceTargetContext", "invalidateTarget",
                             "reconcileTargetConsumers", "traceFocus", "traceView")
        functions = ",".join(f"{name}:{qml_handler(name, 'provider.qml')}" for name in names)
        script = (HARNESS.replace("DELAY", "0").replace("FUNCTIONS", functions)
                  .replace("OWNER_FINISHED", signal_handler("id: ownerLookup\n", "onFinished"))
                  .replace("READER_FINISHED", signal_handler("id: reader\n", "onFinished"))
                  .replace("WRITER_FINISHED", signal_handler("id: writer\n", "onFinished"))
                  .replace("WRITER_FAILED", signal_handler("id: writer\n", "onFailed", ""))
                  .replace("TIMER_TRIGGERED", signal_handler("id: delayed\n", "onTriggered",
                                                             "delayed")))
        # The focus and view traces return at once with their probes off: no Workspace needed.
        script += ("Object.assign(probe, {targetProbe: true, focusProbe: false,"
                   " viewLossProbe: false, targetGeneration: 0, targetHandoff: null,"
                   " preparedTarget: null, preparationFailure: '', lastEligibleWindow: null,"
                   " targetConsumers: [], targetInventoryComplete: false, shellPid: 0,"
                   " shellPidOwner: ''});\n"
                   "const shellIdentityLookup = {arguments: [], call: () => calls.push('pid')};\n"
                   "const pidFinished = "
                   + signal_handler("id: shellIdentityLookup\n", "onFinished") + ";\n"
                   "const pidFailed = "
                   + signal_handler("id: shellIdentityLookup\n", "onFailed", "") + ";\n")
        result = subprocess.run(["node", "-"], input=script + action, capture_output=True,
                                text=True, timeout=10, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_a_failed_shell_pid_lookup_does_not_schedule_another_read(self):
        # The failure still advances the context; only the next wake-up or event reads again.
        for failure in ("pidFailed()", "pidFinished([0])"):
            with self.subTest(failure=failure):
                out = self.run_target_lookup(
                    f"probe.scan(); ownerFinished([':1.5']); {failure}; drain();"
                    " emit({owners: count('owner'), reading: probe.reading,"
                    " generation: probe.targetGeneration});")
                self.assertEqual(out, {"owners": 1, "reading": False, "generation": 1})

    def test_a_wake_during_a_failed_shell_pid_lookup_keeps_its_read(self):
        for failure in ("pidFailed()", "pidFinished([0])"):
            with self.subTest(failure=failure):
                out = self.run_target_lookup(
                    f"probe.scan(); ownerFinished([':1.5']); probe.scan(); {failure}; drain();"
                    " emit({owners: count('owner'), reading: probe.reading});")
                self.assertEqual(out, {"owners": 2, "reading": True})


class DefaultReaderBoundTests(unittest.TestCase):
    def snapshot(self, texts: list) -> list:
        script = """
const vm = require('node:vm');
const probe = {targetProbe: false};
const reader = {arguments: [], call: () => {}};
""" + qml_handler("readMailboxes", "provider.qml") + """
readMailboxes();
let snapshot;
vm.runInNewContext(reader.arguments[0], {
    panels: () => [{widgets: () => TEXTS.map((text, index) => ({
        id: index + 1, currentConfigGroup: [], readConfig: () => text
    }))}],
    print: text => { snapshot = JSON.parse(text); }
});
process.stdout.write(JSON.stringify(snapshot));
""".replace("TEXTS", json.dumps(texts))
        result = subprocess.run(["node", "-"], input=script, capture_output=True, text=True,
                                timeout=10, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_default_reader_visits_at_most_sixteen_widgets(self):
        texts = [json.dumps({"consumer": f"c{index}", "request": 1}) for index in range(17)]
        rows = self.snapshot(texts)
        self.assertEqual([row["consumer"] for row in rows], [f"c{index}" for index in range(16)])

    def test_default_reader_skips_oversized_or_invalid_requests(self):
        valid = json.dumps({"consumer": "kept", "request": 3})
        texts = [valid, json.dumps({"consumer": "big", "request": 1, "pad": "x" * 2048}),
                 json.dumps({"consumer": "", "request": 1}),
                 json.dumps({"consumer": "c" * 129, "request": 1}),
                 json.dumps({"consumer": "zero", "request": 0}),
                 json.dumps({"consumer": "half", "request": 1.5}),
                 json.dumps({"consumer": "huge", "request": 2147483647}), "not-json"]
        self.assertEqual([(row["id"], row["consumer"]) for row in self.snapshot(texts)],
                         [(1, "kept")])


class PipelineSourceTests(unittest.TestCase):
    def test_writer_completion_and_failure_both_resume_the_pipeline(self):
        for signal in ("onFinished", "onFailed"):
            with self.subTest(signal=signal):
                self.assertIn("probe.publicationFinished()",
                              signal_handler("id: writer\n", signal, "" if signal == "onFailed"
                                             else "value"))


class PipelineSeedTests(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory(prefix="pf-pipeline-seed-")
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
            [sys.executable, str(PREPARER), "--stage", str(self.stage),
             "--output", str(self.output), *arguments],
            cwd=self.root, capture_output=True, text=True, timeout=10, check=False,
        )

    def test_pipeline_seed_marks_the_case_and_hashes_its_inputs(self):
        result = self.run_seed("--pipeline-probe")
        self.assertEqual(result.returncode, 0, result.stderr)
        config = (self.output / ".config/kwinrc").read_text()
        for setting in ("plasmafusion-layout-probeEnabled=true", "PipelineProbe=true",
                        "RefusedBackendProbe=false", "TargetProbe=false", "ReplyDelayMs=0"):
            self.assertIn(setting, config)
        manifest = json.loads((self.output / "probe-inputs.json").read_text())
        for name in ("pipeline.py", "pipeline_scenario.sh", "mixed_lifetime.py", "cleanup.py"):
            copied = (self.output / ".local/lib/layout-control" / name).read_bytes()
            self.assertEqual(copied, (HERE / name).read_bytes())
            self.assertEqual(manifest[name], hashlib.sha256(copied).hexdigest())

    def test_default_seed_keeps_the_pipeline_case_off(self):
        result = self.run_seed()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("PipelineProbe=false", (self.output / ".config/kwinrc").read_text())
        manifest = json.loads((self.output / "probe-inputs.json").read_text())
        for name in ("pipeline.py", "pipeline_scenario.sh"):
            self.assertNotIn(name, manifest)

    def test_pipeline_case_is_a_separate_plain_transport_case(self):
        for extra in (("--target-probe",), ("--focus-probe",), ("--mixed-lifetime-probe",),
                      ("--view-loss-probe",), ("--refused-backend-probe",),
                      ("--drop-retirement-frame",),
                      ("--query-timeout-ms", "200", "--reply-delay-ms", "2000")):
            with self.subTest(extra=extra):
                result = self.run_seed("--pipeline-probe", *extra)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("pipeline case", result.stderr)
                self.assertFalse(self.output.exists())


BOOTS = ("1795000000001:0.11", "1795000000002:0.22")
EPOCH = "e" * 32


class PipelineRun:
    """Synthetic raw evidence in the order the native scenario produces it."""

    def __init__(self, root: Path):
        self.root, self.kwin, self.shell = root, [], []
        self.request = {boot: 1 for boot in BOOTS}
        self.revision = 0

    def flush(self) -> None:
        (self.root / "kwin.log").write_text("".join(self.kwin))
        (self.root / "plasmashell.log").write_text("".join(self.shell))

    def backend(self, text: str) -> None:
        self.kwin.append(f"qml: layout-probe: {text}\n")

    def frame(self, boot: str, request: int) -> dict:
        """A frame as the consumer logs its reception; revisions follow the provider's counter."""
        self.revision += 1
        packet = {"consumer": boot, "epoch": EPOCH, "revision": self.revision,
                  "status": "online", "capable": True, "refusal": -1, "request": request,
                  "backendOwner": ":1.0", "identityName": "org.plasmafusion.LayoutProbe.p" + EPOCH}
        self.shell.append("qml: layout-probe-received "
                          + json.dumps(packet | {"receiverBoot": boot}) + "\n")
        return packet

    def accept(self, boot: str, packet: dict) -> None:
        row = {"boot": boot, "phase": "online", "epoch": EPOCH, "revision": packet["revision"],
               "accepted": packet["revision"], "packet": packet, "request": self.request[boot]}
        self.shell.append("qml: layout-probe-observation " + json.dumps(row) + "\n")

    def settle(self, boot: str, *, request=None) -> None:
        self.accept(boot, self.frame(boot, self.request[boot] if request is None else request))

    def cycle(self, *, wakes_while_reading=0, wakes_while_publishing=0, overlap=False,
              unfinished=False, double=False, concurrent=False, failed=False,
              unrecognized=False) -> None:
        """One serialized read and publication, with wakes arriving while each is busy."""
        self.backend("read started")
        if concurrent:
            self.backend("read started")
            self.backend("read finished")
        for _ in range(wakes_while_reading):
            self.backend("wake received")
        self.backend("mailbox rows 2")
        self.backend("publication online 2")
        if double:
            self.backend("publication online 2")
        if overlap:
            self.backend("read finished")
            self.backend("read started")
        self.backend("read finished")
        for _ in range(wakes_while_publishing):
            self.backend("wake received")
        if unrecognized:
            self.backend("publication writes two")
        if failed:
            self.backend("publication failed")
        elif not unfinished:
            self.backend("publication writes 2")

    def mark(self, label: str) -> None:
        self.flush()
        checker().mark(self.root, label)

    def step(self, name: str) -> dict:
        self.flush()
        return checker().record_step(self.root, name)

    def build(self, *, wakes=6, overlap=False, unfinished=False, idle_burst=False,
              uncoalesced=False, unsettled=False, double=False, stale_consumers=False,
              concurrent=False, lost=False, late_pre_burst=False, failed_publication=False,
              unrecognized=False) -> None:
        self.cycle()
        for boot in BOOTS:
            self.settle(boot)
        late = {}
        if late_pre_burst:
            # A second pre-burst publication whose frames are accepted only after the mark.
            self.cycle()
            late = {boot: self.frame(boot, self.request[boot]) for boot in BOOTS}
        self.mark("burst")
        if idle_burst:
            for _ in range(wakes):
                self.backend("wake received")
                self.cycle()
        elif uncoalesced:
            # Every wake-up gets its own read: nothing is lost, and nothing coalesces.
            for _ in range(wakes):
                self.cycle(wakes_while_publishing=1)
            self.cycle()
        elif lost:
            # Every wake-up meets the publication, and no read follows.
            self.cycle(wakes_while_publishing=wakes)
        else:
            self.cycle(wakes_while_reading=wakes // 2, wakes_while_publishing=wakes - wakes // 2,
                       overlap=overlap, double=double, concurrent=concurrent,
                       unrecognized=unrecognized)
            self.cycle(unfinished=unfinished, failed=failed_publication)
        for boot in BOOTS:
            if stale_consumers:
                break
            if late_pre_burst:
                self.accept(boot, late[boot])
                continue
            if unsettled:
                self.request[boot] += 1
            self.settle(boot, request=1 if unsettled else None)
        self.step("settled")


class PipelineCheckerTests(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory(prefix="pf-pipeline-check-")
        self.addCleanup(scratch.cleanup)
        self.root = Path(scratch.name)
        write_cleanup_fixture(self.root)
        (self.root / "pipeline-burst.json").write_text(json.dumps({"schema": 1, "wakes": 6}))
        self.run_ = PipelineRun(self.root)

    def assert_rejected(self, message: str, **variant) -> None:
        with self.assertRaisesRegex(ValueError, message):
            self.run_.build(**variant)
            checker().write_receipt(self.root)
        self.assertFalse((self.root / "pipeline-result.json").exists())

    def test_serialized_coalesced_burst_passes_and_counts_the_work(self):
        self.run_.build()
        checker().write_receipt(self.root)
        receipt = json.loads((self.root / "pipeline-result.json").read_text())
        self.assertEqual(receipt, {"schema": 1, "passed": True, "checks": checker().CHECKS})
        settled = json.loads((self.root / "pipeline-settled.json").read_text())
        self.assertEqual({key: settled["counts"][key] for key in
                          ("wakes", "reads", "publications", "saves")},
                         {"wakes": 6, "reads": 2, "publications": 2, "saves": 4})
        with self.assertRaises(OSError):
            checker().write_receipt(self.root)

    def test_read_started_during_a_publication_fails(self):
        self.assert_rejected("read started while a publication was outstanding", overlap=True)

    def test_read_started_during_another_read_fails(self):
        self.assert_rejected("a read started while another read was running", concurrent=True)

    def test_second_publication_while_one_is_outstanding_fails(self):
        self.assert_rejected("more than one publication outstanding", double=True)

    def test_unfinished_publication_fails(self):
        self.assert_rejected("not settled", unfinished=True)

    def test_burst_that_never_met_a_busy_pipeline_fails(self):
        self.assert_rejected("no wake arrived while the pipeline was busy", idle_burst=True)

    def test_burst_without_coalescing_fails(self):
        self.assert_rejected("did not coalesce", uncoalesced=True)

    def test_consumers_not_on_their_current_request_fail(self):
        self.assert_rejected("did not settle online", unsettled=True)

    def test_wake_never_followed_by_a_read_fails(self):
        # Coalesced, not lost: every wake-up must be followed by a read.
        self.assert_rejected("never followed by a read", lost=True)

    def test_late_acceptance_of_a_pre_burst_frame_fails(self):
        self.assert_rejected("published after the burst", late_pre_burst=True)

    def test_failed_publication_still_resumes_and_is_counted(self):
        self.run_.build(failed_publication=True)
        checker().write_receipt(self.root)
        counts = json.loads((self.root / "pipeline-settled.json").read_text())["counts"]
        self.assertEqual((counts["failedPublications"], counts["saves"], counts["reads"]),
                         (1, 2, 2))

    def test_unrecognized_pipeline_line_fails(self):
        self.assert_rejected("unrecognized pipeline line", unrecognized=True)

    def test_consumers_without_a_frame_after_the_burst_fail(self):
        self.assert_rejected("after the burst", stale_consumers=True)

    def test_mark_and_step_records_are_written_once(self):
        self.run_.build()
        with self.assertRaises(FileExistsError):
            checker().mark(self.root, "burst")
        with self.assertRaises(FileExistsError):
            checker().record_step(self.root, "settled")

    def test_missing_burst_wakes_fail(self):
        (self.root / "pipeline-burst.json").write_text(json.dumps({"schema": 1, "wakes": 7}))
        self.assert_rejected("expected 7 wakes")

    def test_tampered_record_fails_recomputation(self):
        self.run_.build()
        record = self.root / "pipeline-settled.json"
        value = json.loads(record.read_text())
        value["counts"]["reads"] = 1
        record.write_text(json.dumps(value))
        with self.assertRaisesRegex(ValueError, "does not match its raw evidence"):
            checker().write_receipt(self.root)

    def test_check_result_requires_the_receipt_and_rechecks_the_evidence(self):
        self.run_.build()
        (self.root / "scenario.log").write_text("scenario rc=0\nsession rc=0\n")
        check = [sys.executable, str(PREPARER), "--check-result", str(self.root),
                 "--scope", "pipeline"]
        missing = subprocess.run(check, capture_output=True, text=True, timeout=10, check=False)
        self.assertNotEqual(missing.returncode, 0)
        self.assertIn("missing probe receipt", missing.stderr)
        checker().write_receipt(self.root)
        passed = subprocess.run(check, capture_output=True, text=True, timeout=10, check=False)
        self.assertEqual(passed.returncode, 0, passed.stderr)
        record = self.root / "pipeline-settled.json"
        value = json.loads(record.read_text())
        value["counts"]["saves"] = 0
        record.write_text(json.dumps(value))
        tampered = subprocess.run(check, capture_output=True, text=True, timeout=10, check=False)
        self.assertNotEqual(tampered.returncode, 0)
        self.assertIn("does not match its raw evidence", tampered.stderr)


class PipelineScenarioTests(unittest.TestCase):
    def test_bridge_branches_after_the_first_online_exchange(self):
        bridge = (HERE / "scenario-bridge.sh").read_text()
        identity = bridge.index('[[ $identity_owner == "$backend_owner" ]] || return 1')
        branch = bridge.index("--key PipelineProbe")
        sourced = bridge.index('source "$HOME/.local/lib/layout-control/pipeline_scenario.sh"')
        focus = bridge.index("--key FocusProbe")
        self.assertLess(identity, branch)
        self.assertLess(branch, sourced)
        self.assertLess(sourced, focus)
        tail = bridge[sourced:focus]
        self.assertLess(tail.index("finish_probe_session"), tail.index("return 0"))

    def test_burst_is_marked_parallel_and_waited_for(self):
        scenario = (HERE / "pipeline_scenario.sh").read_text()
        # Wait only for the burst's own clients: the sourced shell also owns the session.
        # The wake command itself ends in the background operator, uncommented.
        order = ['pipeline_mark burst', '"$OUT/pipeline-burst.json"', "invokeShortcut",
                 '"Plasma Fusion: Layout Probe Wake" >/dev/null &\n',
                 'pipeline_pids+=("$!")', 'for pipeline_pid in "${pipeline_pids[@]}"; do',
                 'wait "$pipeline_pid"', "pipeline_failed + 1", "pipeline_wait settled",
                 '"$pipeline_helper" receipt "$OUT"']
        cursor = 0
        for item in order:
            cursor = scenario.index(item, cursor)
        self.assertRegex(scenario, re.compile(r"^set -euo pipefail$", re.M))
        for forbidden in ("kwriteconfig", "reconfigure", "systemctl", "ssh ", "sudo", "podman"):
            self.assertNotIn(forbidden, scenario)
        guard = scenario[:scenario.index("pipeline_mark()")]
        for requirement in ("/var/tmp/pfv-layout-control-*", "PF_LAYOUT_PRIVATE_CONTAINER",
                            "/run/.containerenv"):
            self.assertIn(requirement, guard)

    def test_a_failed_wake_up_dispatch_stops_the_burst(self):
        # The burst's own text, in bash under errexit: the first client fails, the rest succeed.
        # wait with several PIDs would report only the last one, and polling would then start.
        scenario = (HERE / "pipeline_scenario.sh").read_text()
        burst = scenario.split("pipeline_pids=()\n", 1)[1].split("pipeline_wait settled\n", 1)[0]
        script = ("set -euo pipefail\n"
                  "qdbus() { [[ $wake != 0 ]]; }\n"
                  f"burst() {{\npipeline_pids=()\n{burst}}}\n"
                  "pipeline_wakes=24\nburst\necho polling\n")
        result = subprocess.run(["/usr/bin/bash", "-c", script], env={"PATH": "/usr/bin:/bin"},
                                capture_output=True, text=True, timeout=30, check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("polling", result.stdout)
        self.assertIn("FAIL: 1 of 24 wake-up dispatches failed", result.stderr)
