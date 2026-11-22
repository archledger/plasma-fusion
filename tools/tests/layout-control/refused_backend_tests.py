# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Refused and absent native backend cases, re-exported by the existing test entry point."""

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
PREPARER = HERE / "prepare_seed.py"
NULL_UUID = "{00000000-0000-0000-0000-000000000000}"
ALIAS = "org.plasmafusion.LayoutProbe.p"
MUTATING = ("createTile", "admitTile", "releaseTile", "writeConfig", "frameGeometry", "setMaximize")


def checker():
    """Import lazily: a missing checker fails these cases, not the whole entry point."""
    name = f"{__package__}.refused_backend" if __package__ else "refused_backend"
    return importlib.import_module(name)


def md5(text: str) -> str:
    return hashlib.md5(text.encode()).hexdigest()


def block(source: str, opening: str) -> str:
    """Body of a QML block such as 'Component.onCompleted: {'."""
    start = source.index(opening)
    index = source.index("{", start)
    depth, end = 1, index + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[index:end]


PRELUDE = r"""
// Hoisted declarations already exist here, so only globals the code under test adds remain.
const globalsBefore = new Set(Object.getOwnPropertyNames(globalThis));
const crypto = require('node:crypto');
const Qt = {md5: text => crypto.createHash('md5').update(String(text)).digest('hex'),
            rect: (x, y, width, height) => ({x, y, width, height})};
const logs = [], registered = [], tokens = [];
console.info = (...args) => logs.push(args.map(String).join(' '));
console.warn = console.info;
// Everything the code under test kept: the object's own data and any global it added, both
// serialized in full so that a token nested in an object is still visible. A repeated object is
// written once, so a record that points back to its owner keeps every other field. There is no
// fallback: a value this cannot serialize makes node exit non-zero, which fails the case.
function retained(object) {
    const seen = new WeakSet();
    const data = (key, value) => {
        if (typeof value === 'function') {
            return undefined;
        }
        if (value !== null && typeof value === 'object') {
            if (seen.has(value)) {
                return '[repeated]';
            }
            seen.add(value);
        }
        return value;
    };
    const added = Object.getOwnPropertyNames(globalThis).filter(name => !globalsBefore.has(name));
    return JSON.stringify([object, added.map(name => [name, globalThis[name]])], data);
}
"""
ABSENT = "const Workspace = {currentDesktop:{id:'d'}};"
NULL_API = "const Workspace = {currentDesktop:{id:'d'}, transientTiling: () => null};"
# One fresh native writer per lifetime, as after the previous provider object was destroyed.
FAKE_API = """
const Workspace = {currentDesktop:{id:'d'}, transientTiling: () => {
    let holder = OCCUPIED;
    return {
        registerProvider: provider => {
            registered.push(provider.role || 'probe');
            if (WRITER_MISSING) return '';
            if (holder !== null) return NULL;
            holder = provider;
            const token = '{' + crypto.randomUUID() + '}';
            tokens.push(token);
            return token;
        },
        createTile: (output, desktop, rect) => ({result: output && desktop ? 0 : -1, generation: 0})
    };
}};
"""


def fake_api(*, occupied: bool = False, writer_missing: bool = False) -> str:
    return (FAKE_API.replace("OCCUPIED", "{role:'occupier'}" if occupied else "null")
            .replace("WRITER_MISSING", "true" if writer_missing else "false")
            .replace("NULL", json.dumps(NULL_UUID)))


class RefusedRegistrationTests(unittest.TestCase):
    """Run the provider's actual native registration code against fake native APIs."""

    def lifetimes(self, workspace: str) -> dict:
        functions = ",".join(f"{name}:{qml_handler(name, 'provider.qml')}"
                             for name in ("providerAccepted", "newLifetimeLabel", "registerNative"))
        script = PRELUDE + workspace + r"""
function lifetime() {
    const probe = {epoch:'stock', capable:false, refusal:0, competingProviderRejected:false,
                   competingProvider:{role:'competitor'}};
    const methods = (function(){with(probe){return {FUNCTIONS};}})();
    Object.assign(probe, methods);
    const returned = probe.registerNative();
    return {epoch:probe.epoch, capable:probe.capable, refusal:probe.refusal,
            competingProviderRejected:probe.competingProviderRejected, retained:retained(probe),
            returned:typeof returned};
}
const results = [lifetime(), lifetime()];
process.stdout.write(JSON.stringify({results, logs, registered, tokens}));
""".replace("FUNCTIONS", functions)
        result = subprocess.run(["node", "-"], input=script, capture_output=True, text=True,
                                timeout=10, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def assert_fresh_labels(self, results: list) -> None:
        epochs = [row["epoch"] for row in results]
        for epoch in epochs:
            self.assertRegex(epoch, r"^[0-9a-f]{32}$")
        self.assertNotEqual(epochs[0], epochs[1], "a later lifetime reused the provider label")

    def test_absent_native_api_is_incapable_with_a_fresh_label_per_lifetime(self):
        out = self.lifetimes(ABSENT)
        for row in out["results"]:
            self.assertEqual((row["capable"], row["refusal"], row["competingProviderRejected"]),
                             (False, 0, False))
        self.assert_fresh_labels(out["results"])
        self.assertEqual(out["registered"], [])

    def test_missing_api_object_or_writer_is_incapable(self):
        for name, workspace in (("null api", NULL_API),
                                ("no writer", fake_api(writer_missing=True))):
            with self.subTest(name):
                out = self.lifetimes(workspace)
                self.assertFalse(any(row["capable"] for row in out["results"]))
                self.assert_fresh_labels(out["results"])
                self.assertNotIn(md5(""), [row["epoch"] for row in out["results"]])

    def test_refused_registration_is_incapable_and_never_reuses_a_label(self):
        out = self.lifetimes(fake_api(occupied=True))
        for row in out["results"]:
            self.assertEqual((row["capable"], row["refusal"], row["competingProviderRejected"]),
                             (False, -1, True))
            self.assertNotEqual(row["epoch"], md5(NULL_UUID),
                                "the label was derived from the refused token")
        self.assert_fresh_labels(out["results"])
        self.assertEqual(out["registered"], ["probe", "competitor"] * 2)

    def test_accepted_label_is_independent_of_the_ownership_token(self):
        out = self.lifetimes(fake_api())
        self.assertEqual(len(out["tokens"]), 2)
        for row, token in zip(out["results"], out["tokens"]):
            self.assertEqual((row["capable"], row["refusal"], row["competingProviderRejected"]),
                             (True, -1, True))
            self.assertNotEqual(row["epoch"], md5(token))
        self.assert_fresh_labels(out["results"])

    def test_registration_never_keeps_logs_or_returns_a_token(self):
        out = self.lifetimes(fake_api())
        # The results include everything the probe object and the globals hold afterwards.
        visible = json.dumps([out["logs"], out["results"]])
        self.assertEqual(len(out["tokens"]), 2)
        for token in out["tokens"]:
            self.assertNotIn(token.strip("{}"), visible)
        # Declared void: it returns nothing, so no caller can receive the token from it.
        self.assertEqual([row["returned"] for row in out["results"]], ["undefined"] * 2)

    def test_component_completion_uses_the_tested_registration(self):
        source = (HERE / "provider.qml").read_text()
        body = block(source, "Component.onCompleted: {")
        self.assertIn("registerNative();", body)
        self.assertNotIn("registerProvider", body)
        self.assertNotIn("Qt.md5(token", source)
        self.assertLess(body.index("registerNative();"), body.index("identityName ="))
        # An unauthorized probe must stay inert: it may not take the native slot.
        guard = body.index("if (!authorized) {")
        self.assertLess(body.index('KWin.readConfig("ProbeAuthorized"'), guard)
        self.assertLess(body.index("return;", guard), body.index("registerNative();"))


class OccupierTests(unittest.TestCase):
    """The occupier fixture only holds the native provider slot."""

    def occupy(self, authorized: bool, token: str) -> dict:
        function = qml_handler("occupy", "occupier.qml")
        script = PRELUDE + r"""
const KWin = {readConfig: (key, fallback) => key === 'OccupierAuthorized' ? AUTHORIZED : fallback};
const occupier = {authorized:false, accepted:false};
const Workspace = {transientTiling: () => ({registerProvider: provider => {
    registered.push(provider === occupier);
    return TOKEN;
}})};
const methods = (function(){with(occupier){return {occupy:FUNCTION};}})();
Object.assign(occupier, methods);
occupier.occupy();
process.stdout.write(JSON.stringify({authorized:occupier.authorized, accepted:occupier.accepted,
                                     logs, registered, retained:retained(occupier)}));
""".replace("AUTHORIZED", "true" if authorized else "false").replace(
            "TOKEN", json.dumps(token)).replace("FUNCTION", function)
        result = subprocess.run(["node", "-"], input=script, capture_output=True, text=True,
                                timeout=10, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_occupier_holds_the_native_slot_and_logs_only_its_verdict(self):
        token = "{0b1d2c3e-4f50-4a6b-8c7d-9e0f1a2b3c4d}"
        out = self.occupy(True, token)
        self.assertEqual((out["authorized"], out["accepted"], out["registered"]),
                         (True, True, [True]))
        self.assertEqual(out["logs"], ["layout-occupier: registered true"])
        self.assertNotIn(token.strip("{}"), json.dumps(out))

    def test_occupier_reports_a_refused_slot(self):
        out = self.occupy(True, NULL_UUID)
        self.assertEqual((out["accepted"], out["logs"]),
                         (False, ["layout-occupier: registered false"]))

    def test_occupier_stays_inert_without_its_marker(self):
        out = self.occupy(False, "{0b1d2c3e-4f50-4a6b-8c7d-9e0f1a2b3c4d}")
        self.assertEqual((out["authorized"], out["accepted"], out["registered"]),
                         (False, False, []))
        self.assertTrue(out["logs"] and "authorization marker absent" in out["logs"][0])

    def test_occupier_never_mutates_windows_tiles_or_configuration(self):
        source = (HERE / "occupier.qml").read_text()
        for name in MUTATING:
            self.assertNotIn(name, source)
        self.assertIn("registerProvider(occupier)", source)
        self.assertIn('console.info("layout-occupier: released", accepted)', source)
        self.assertIn("occupy();", block(source, "Component.onCompleted: {"))


class RefusedSeedTests(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory(prefix="pf-refused-seed-")
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

    def test_refused_seed_starts_only_the_occupier_and_hashes_every_case_input(self):
        result = self.run_seed("--refused-backend-probe")
        self.assertEqual(result.returncode, 0, result.stderr)
        config = (self.output / ".config/kwinrc").read_text()
        for setting in ("plasmafusion-layout-probeEnabled=false",
                        "plasmafusion-layout-occupierEnabled=true", "RefusedBackendProbe=true",
                        "OccupierAuthorized=true", "ProbeAuthorized=true", "FocusProbe=false",
                        "TargetProbe=false", "DropRetirementFrame=false", "ReplyDelayMs=0"):
            self.assertIn(setting, config)
        package = self.output / ".local/share/kwin/scripts/plasmafusion-layout-occupier"
        metadata = json.loads((package / "metadata.json").read_text())
        self.assertEqual((metadata["KPackageStructure"], metadata["KPlugin"]["Id"],
                          metadata["X-Plasma-API"], metadata["X-Plasma-MainScript"]),
                         ("KWin/Script", "plasmafusion-layout-occupier", "declarativescript",
                          "ui/main.qml"))
        installed = (package / "contents/ui/main.qml").read_bytes()
        self.assertEqual(installed, (HERE / "occupier.qml").read_bytes())
        manifest = json.loads((self.output / "probe-inputs.json").read_text())
        self.assertEqual(manifest["occupier.qml"], hashlib.sha256(installed).hexdigest())
        for name in ("refused_backend.py", "refused_scenario.sh", "mixed_lifetime.py",
                     "cleanup.py"):
            copied = (self.output / ".local/lib/layout-control" / name).read_bytes()
            self.assertEqual(copied, (HERE / name).read_bytes())
            self.assertEqual(manifest[name], hashlib.sha256(copied).hexdigest())

    def test_default_seed_keeps_the_refused_case_off(self):
        result = self.run_seed()
        self.assertEqual(result.returncode, 0, result.stderr)
        config = (self.output / ".config/kwinrc").read_text()
        self.assertIn("plasmafusion-layout-probeEnabled=true", config)
        self.assertIn("RefusedBackendProbe=false", config)
        self.assertNotIn("occupier", config)
        occupier = self.output / ".local/share/kwin/scripts/plasmafusion-layout-occupier"
        self.assertFalse(occupier.exists())
        manifest = json.loads((self.output / "probe-inputs.json").read_text())
        for name in ("occupier.qml", "refused_backend.py", "refused_scenario.sh"):
            self.assertNotIn(name, manifest)

    def test_refused_case_is_a_separate_plain_transport_case(self):
        for extra in (("--target-probe",), ("--focus-probe",), ("--mixed-lifetime-probe",),
                      ("--view-loss-probe",), ("--drop-retirement-frame",),
                      ("--query-timeout-ms", "200", "--reply-delay-ms", "2000")):
            with self.subTest(extra=extra):
                result = self.run_seed("--refused-backend-probe", *extra)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("refused-backend case", result.stderr)
                self.assertFalse(self.output.exists())


BOOTS = ("1795000000001:0.11", "1795000000002:0.22")
E1, E2, E3 = md5("refused-one"), md5("refused-two"), md5("accepted-three")


class RefusedRun:
    """Synthetic raw evidence written in the same order as the native scenario."""

    def __init__(self, root: Path):
        self.root, self.kwin, self.shell = root, [], []
        self.request = {boot: 1 for boot in BOOTS}
        self.revision = 0

    def flush(self) -> None:
        (self.root / "kwin.log").write_text("".join(self.kwin))
        (self.root / "plasmashell.log").write_text("".join(self.shell))

    def backend(self, text: str) -> None:
        self.kwin.append(f"qml: {text}\n")

    def observe(self, boot: str, phase: str, epoch: str, packet) -> None:
        self.shell.append("qml: layout-probe-observation " + json.dumps({
            "boot": boot, "phase": phase, "epoch": epoch,
            "revision": packet["revision"] if packet else -1, "accepted": 0, "packet": packet,
            "request": self.request[boot]}) + "\n")

    def frame(self, boot: str, epoch: str, capable: bool, status: str, *,
              alias: str = ALIAS) -> dict:
        self.revision += 1
        packet = {"consumer": boot, "epoch": epoch, "revision": self.revision, "status": status,
                  "capable": capable, "refusal": -1, "request": self.request[boot],
                  "preparation": None, "targetContext": None, "competingProviderRejected": True,
                  "backendOwner": ":1.0", "identityName": alias + epoch}
        self.shell.append("qml: layout-probe-received "
                          + json.dumps(packet | {"receiverBoot": boot}) + "\n")
        return packet

    def deliver(self, boot: str, epoch: str, capable: bool, *, alias: str = ALIAS,
                phase: str = "") -> None:
        packet = self.frame(boot, epoch, capable, "online", alias=alias)
        self.observe(boot, phase or ("online" if capable else "unsupported"), epoch, packet)

    def drop(self, boot: str) -> None:
        """The consumer's fresh query: its binding is gone and its request advances."""
        self.request[boot] += 1
        self.observe(boot, "unknown", "", None)

    def retire(self, boot: str, previous: str, upcoming: str, capable: bool, how: str) -> None:
        """One of the three racing ways the real consumer leaves a provider lifetime."""
        if how == "invalidate":
            self.shell.append("qml: layout-probe-invalidated "
                              + json.dumps({"boot": boot, "name": ALIAS + previous}) + "\n")
            self.drop(boot)
        elif how == "offline":
            # The previous provider's accepted retirement frame.
            packet = self.frame(boot, previous, False, "offline")
            self.observe(boot, "offline", previous, packet)
            self.drop(boot)
        elif how == "replaced":
            # The next provider's first frame answers the old request; it is never accepted.
            self.frame(boot, upcoming, capable, "online")
            self.drop(boot)
        # "none": the consumer keeps the previous binding.

    def late(self, previous: str, how: str | None) -> None:
        """A newer frame of the previous lifetime accepted after the step's mark.

        The provider publishes once per wake and each consumer verifies one frame at a time, so
        a step can be confirmed between a consumer's two acceptances of one lifetime.
        """
        if how is None:
            return
        for boot in BOOTS:
            self.request[boot] += how == "another-request"
            self.deliver(boot, previous, False)
            self.request[boot] -= how == "another-request"

    def mark(self, label: str) -> None:
        self.flush()
        checker().mark(self.root, label)

    def step(self, name: str) -> dict:
        self.flush()
        return checker().record_step(self.root, name)

    def build(self, *, epochs=(E1, E2, E3), refused_online=False, release_early=False,
              first_capable=False, alias=ALIAS, retire="invalidate", returned=False,
              stale_request=False, capable_after_release=False, capable_frame=False,
              late_previous=None, left_between=False) -> None:
        first, second, third = epochs
        self.backend("layout-occupier: registered true")
        self.mark("start")
        self.step("occupied")
        self.mark("load-1")
        self.backend(f"layout-probe: initialized {'true' if first_capable else 'false'} -1")
        for boot in BOOTS:
            self.observe(boot, "unknown", "", None)
            if capable_frame:
                # Published for an old request, so the consumer never accepts it.
                self.request[boot] -= 1
                self.frame(boot, first, True, "online", alias=alias)
                self.request[boot] += 1
            self.deliver(boot, first, refused_online, alias=alias)
        self.step("refused-1")
        self.mark("reload-1")
        if release_early:
            self.backend("layout-occupier: released true")
        self.late(first, late_previous)
        self.backend("layout-probe: initialized false -1")
        for boot in BOOTS:
            self.retire(boot, first, second, False, retire)
            if returned:
                # A frame of the previous lifetime accepted after the binding was dropped.
                self.deliver(boot, first, False)
            if stale_request:
                self.request[boot] -= 1
            self.deliver(boot, second, False, alias=alias)
        self.step("refused-2")
        if left_between:
            # Settled on the second lifetime, a frame of the first is accepted before the release
            # mark, where no step's window reads it.
            self.deliver(BOOTS[0], first, False)
        self.mark("release")
        if not release_early:
            self.backend("layout-occupier: released true")
        if capable_after_release:
            # The still-refused lifetime may not turn capable when the slot becomes free.
            self.deliver(BOOTS[0], second, True)
        self.step("released")
        self.mark("reload-2")
        self.late(second, late_previous)
        self.backend("layout-probe: initialized true -1")
        for boot in BOOTS:
            self.retire(boot, second, third, True, retire)
            self.deliver(boot, third, True, alias=alias)
        self.step("accepted")


class RefusedCheckerTests(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory(prefix="pf-refused-check-")
        self.addCleanup(scratch.cleanup)
        self.root = Path(scratch.name)
        write_cleanup_fixture(self.root)
        self.run_ = RefusedRun(self.root)

    def test_complete_refused_run_passes_and_writes_the_receipt_last(self):
        self.run_.build()
        checker().write_receipt(self.root)
        receipt = json.loads((self.root / "refused-backend-result.json").read_text())
        self.assertEqual(receipt, {"schema": 1, "passed": True, "checks": checker().CHECKS})
        accepted = json.loads((self.root / "refused-accepted.json").read_text())
        self.assertEqual(accepted["epoch"], E3)
        with self.assertRaises(OSError):
            checker().write_receipt(self.root)

    def assert_rejected(self, message: str, **variant) -> None:
        with self.assertRaisesRegex(ValueError, message):
            self.run_.build(**variant)
            checker().write_receipt(self.root)
        self.assertFalse((self.root / "refused-backend-result.json").exists())

    def test_refused_lifetimes_that_share_a_label_fail(self):
        self.assert_rejected("reused a provider label", epochs=(E1, E1, E3))

    def test_accepted_lifetime_reusing_a_refused_label_fails(self):
        self.assert_rejected("reused a provider label", epochs=(E1, E2, E1))

    def test_capable_state_during_a_refused_lifetime_fails(self):
        self.assert_rejected("a consumer accepted capable state during a refused lifetime",
                             refused_online=True)

    def test_capable_frame_during_a_refused_lifetime_fails(self):
        self.assert_rejected("a capable frame was published during a refused lifetime",
                             capable_frame=True)

    def test_capable_first_registration_fails(self):
        self.assert_rejected("refused registration", first_capable=True)

    def test_occupier_released_before_the_second_refusal_fails(self):
        self.assert_rejected("the occupier changed during a provider lifetime", release_early=True)

    def test_alias_not_derived_from_the_label_fails(self):
        self.assert_rejected("identity", alias="org.example.Other.p")

    def test_each_racing_retirement_path_passes(self):
        # Alias invalidation, the accepted retirement frame and the next provider's first frame
        # race in the real consumer; any of them may end the previous binding.
        for how in ("offline", "replaced"):
            with self.subTest(how=how):
                root = self.root / how
                root.mkdir()
                write_cleanup_fixture(root)
                RefusedRun(root).build(retire=how)
                checker().write_receipt(root)
                self.assertTrue((root / "refused-backend-result.json").exists())

    def test_late_frame_of_the_previous_lifetime_passes(self):
        self.run_.build(late_previous="same-request")
        checker().write_receipt(self.root)
        self.assertTrue((self.root / "refused-backend-result.json").exists())

    def test_late_frame_for_another_request_fails(self):
        # The allowance covers only the previous lifetime's own request.
        self.assert_rejected("passed through an unexpected state",
                             late_previous="another-request")

    def test_consumer_keeping_the_previous_binding_fails(self):
        self.assert_rejected("kept the previous provider's state", retire="none")

    def test_consumer_returning_to_the_previous_label_fails(self):
        self.assert_rejected("returned to the previous provider", returned=True)

    def test_consumer_returning_to_a_retired_lifetime_between_steps_fails(self):
        self.assert_rejected("returned to a provider lifetime it had left", left_between=True)

    def test_settling_without_a_fresh_query_fails(self):
        self.assert_rejected("without a fresh query", stale_request=True)

    def test_malformed_event_rows_fail_cleanly(self):
        self.run_.shell.append("qml: layout-probe-observation [1, 2]\n")
        self.assert_rejected("malformed observation event")

    def test_capable_state_before_the_probe_reloads_fails(self):
        self.assert_rejected("before the probe re-registered", capable_after_release=True)

    def test_marks_and_step_records_are_written_once(self):
        self.run_.build()
        with self.assertRaises(FileExistsError):
            checker().mark(self.root, "start")
        with self.assertRaises(FileExistsError):
            checker().record_step(self.root, "accepted")

    def test_check_result_rechecks_the_raw_evidence(self):
        self.run_.build()
        (self.root / "scenario.log").write_text("scenario rc=0\nsession rc=0\n")
        checker().write_receipt(self.root)
        record = self.root / "refused-accepted.json"
        value = json.loads(record.read_text())
        value["capable"] = False
        record.write_text(json.dumps(value))
        result = subprocess.run([sys.executable, str(PREPARER), "--check-result", str(self.root),
                                 "--scope", "refused-backend"],
                                capture_output=True, text=True, timeout=10, check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("accepted record does not match its raw evidence", result.stderr)

    def test_tampered_step_record_fails_recomputation(self):
        self.run_.build()
        record = self.root / "refused-refused-1.json"
        value = json.loads(record.read_text())
        value["epoch"] = E2
        record.write_text(json.dumps(value))
        with self.assertRaisesRegex(ValueError, "does not match its raw evidence"):
            checker().write_receipt(self.root)

    def test_check_result_requires_the_refused_receipt_and_cleanup(self):
        self.run_.build()
        (self.root / "scenario.log").write_text("scenario rc=0\nsession rc=0\n")
        check = [sys.executable, str(PREPARER), "--check-result", str(self.root),
                 "--scope", "refused-backend"]
        missing = subprocess.run(check, capture_output=True, text=True, timeout=10, check=False)
        self.assertNotEqual(missing.returncode, 0)
        self.assertIn("missing probe receipt", missing.stderr)
        checker().write_receipt(self.root)
        passed = subprocess.run(check, capture_output=True, text=True, timeout=10, check=False)
        self.assertEqual(passed.returncode, 0, passed.stderr)
        self.assertIn("PASS: explicit refused-backend receipt", passed.stdout)


class RefusedScenarioTests(unittest.TestCase):
    def test_bridge_branches_before_the_startup_probe_check(self):
        bridge = (HERE / "scenario-bridge.sh").read_text()
        branch = bridge.index("--key RefusedBackendProbe")
        sourced = bridge.index('source "$HOME/.local/lib/layout-control/refused_scenario.sh"')
        startup = bridge.index("isScriptLoaded plasmafusion-layout-probe)")
        self.assertLess(branch, sourced)
        self.assertLess(sourced, startup)
        tail = bridge[sourced:startup]
        self.assertLess(tail.index("finish_probe_session"), tail.index("return 0"))

    def test_refused_scenario_marks_each_step_before_its_native_action(self):
        scenario = (HERE / "refused_scenario.sh").read_text()
        order = ["refused_mark start", "refused_wait occupied", "refused_mark load-1",
                 "refused_load_probe 1", "refused_wait refused-1", "refused_mark reload-1",
                 "refused_unload plasmafusion-layout-probe", "refused_load_probe 1",
                 "refused_wait refused-2", "refused_mark release",
                 "refused_unload plasmafusion-layout-occupier", "refused_wait released",
                 "refused_mark reload-2", "refused_unload plasmafusion-layout-probe",
                 "refused_load_probe 0", "refused_wait accepted",
                 '"$refused_helper" receipt "$OUT"']
        positions = []
        cursor = 0
        for item in order:
            cursor = scenario.index(item, cursor)
            positions.append(cursor)
        self.assertEqual(positions, sorted(positions))

    def test_refused_scenario_runs_only_the_probe_it_loaded(self):
        scenario = (HERE / "refused_scenario.sh").read_text()
        # Scripting.start re-reads [Plugins] and unloads a loaded probe that is disabled there,
        # which this seed's probe is (KWin's Scripting::queryScriptsToLoad). qdbus accepts the
        # method with or without its interface.
        code = "\n".join(line for line in scenario.splitlines()
                         if not line.lstrip().startswith("#"))
        self.assertIsNone(re.search(r"/Scripting\s+(?:org\.kde\.kwin\.Scripting\.)?start\b",
                                    code.replace("\\\n", " ")))
        body = block(scenario, "refused_load_probe() {")
        wait = body.index("refused_loaded plasmafusion-layout-probe false")
        load = body.index("org.kde.kwin.Scripting.loadDeclarativeScript")
        # KWin numbers scripts by count: any other number means the session holds other scripts
        # than assumed, one of which may own that number and object path.
        checked = body.index('[[ $id == "$expected" ]]')
        run = body.index('"/Scripting/Script$id" org.kde.kwin.Script.run')
        self.assertLess(wait, load)
        self.assertLess(load, checked)
        self.assertLess(checked, run)
        calls = re.findall(r"^refused_load_probe (\S+)$", scenario, re.M)
        self.assertEqual(calls, ["1", "1", "0"])

    def test_refused_scenario_changes_only_its_private_session(self):
        scenario = (HERE / "refused_scenario.sh").read_text()
        for forbidden in ("kwriteconfig", "reconfigure", "systemctl", "ssh ", "sudo", "podman"):
            self.assertNotIn(forbidden, scenario)
        self.assertRegex(scenario, re.compile(r"^set -euo pipefail$", re.M))
        guard = scenario[:scenario.index("refused_mark()")]
        for requirement in ("/var/tmp/pfv-layout-control-*", "PF_LAYOUT_PRIVATE_CONTAINER",
                            "/run/.containerenv"):
            self.assertIn(requirement, guard)
