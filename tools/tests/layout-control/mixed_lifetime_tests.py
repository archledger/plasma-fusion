# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Combined lifetime-probe cases, re-exported by the existing test entry point."""

import hashlib
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

if __package__:
    from .cleanup_tests import write_cleanup_fixture
    from .mixed_lifetime import snapshot
    from .qml_helpers import qml_handler
else:
    from cleanup_tests import write_cleanup_fixture
    from mixed_lifetime import snapshot
    from qml_helpers import qml_handler


PREPARER = Path(__file__).with_name("prepare_seed.py")
MIXED = Path(__file__).with_name("mixed_lifetime.py")


class MixedLifetimeSeedTests(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory(prefix="pf-mixed-seed-")
        self.addCleanup(scratch.cleanup)
        self.root = Path(scratch.name)
        self.stage = self.root / "build/stage"
        rules = self.stage / ".local/share/kwin/scripts/plasmafusion-placement/contents/ui/Tiling.js"
        rules.parent.mkdir(parents=True)
        rules.write_text("// private staged rules\n")
        self.output = self.root / "build/seed"

    def run_seed(self, *arguments):
        return subprocess.run(
            [sys.executable, str(PREPARER), "--stage", str(self.stage),
             "--output", str(self.output), *arguments],
            cwd=self.root, capture_output=True, text=True, timeout=10, check=False,
        )

    def test_combined_probe_is_explicit_and_reuses_the_private_target_controls(self):
        result = self.run_seed("--mixed-lifetime-probe")
        self.assertEqual(result.returncode, 0, result.stderr)
        config = (self.output / ".config/kwinrc").read_text()
        for setting in ("MixedLifetimeProbe=true", "TargetProbe=true", "FocusProbe=true",
                        "DropRetirementFrame=false", "ReplyDelayMs=0"):
            self.assertIn(setting, config)
        manifest = json.loads((self.output / "probe-inputs.json").read_text())
        self.assertIn("heldclient.py", manifest)
        self.assertIn("receipts.py", manifest)
        self.assertIn("cleanup.py", manifest)
        self.assertFalse((self.output / ".config/plasma-org.kde.plasma.desktop-appletsrc").exists())

    def test_normal_seed_does_not_enable_the_combined_probe(self):
        result = self.run_seed()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("MixedLifetimeProbe=false", (self.output / ".config/kwinrc").read_text())

    def test_combined_mode_rejects_other_transport_faults_before_creating_a_seed(self):
        for fault in (("--drop-retirement-frame",),
                      ("--query-timeout-ms", "200", "--reply-delay-ms", "2000")):
            with self.subTest(fault=fault):
                result = self.run_seed("--mixed-lifetime-probe", *fault)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("requires normal transport", result.stderr)
                self.assertFalse(self.output.exists())

    def test_result_check_cannot_enable_the_combined_seed_mode(self):
        result = subprocess.run(
            [sys.executable, str(PREPARER), "--check-result", str(self.output),
             "--mixed-lifetime-probe"],
            cwd=self.root, capture_output=True, text=True, timeout=10, check=False,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("--check-result cannot be combined", result.stderr)

    def test_combined_seed_copies_and_hashes_its_exact_evidence_helper(self):
        result = self.run_seed("--mixed-lifetime-probe")
        self.assertEqual(result.returncode, 0, result.stderr)
        manifest = json.loads((self.output / "probe-inputs.json").read_text())
        self.assertIn("mixed_lifetime.py", manifest)
        helper = self.output / ".local/lib/layout-control/mixed_lifetime.py"
        self.assertEqual(helper.read_bytes(), MIXED.read_bytes())
        self.assertEqual(manifest["mixed_lifetime.py"],
                         hashlib.sha256(helper.read_bytes()).hexdigest())

    def test_combined_seed_copies_and_hashes_its_sourced_native_case(self):
        result = self.run_seed("--mixed-lifetime-probe")
        self.assertEqual(result.returncode, 0, result.stderr)
        manifest = json.loads((self.output / "probe-inputs.json").read_text())
        self.assertIn("mixed_scenario.sh", manifest)
        helper = self.output / ".local/lib/layout-control/mixed_scenario.sh"
        self.assertEqual(helper.read_bytes(), MIXED.with_name("mixed_scenario.sh").read_bytes())
        self.assertEqual(manifest["mixed_scenario.sh"],
                         hashlib.sha256(helper.read_bytes()).hexdigest())

    def test_sourced_case_refuses_non_private_context_before_running_any_helper(self):
        result = subprocess.run(
            ["/usr/bin/bash", "-c", 'source "$1"', "mixed-case",
             str(MIXED.with_name("mixed_scenario.sh"))],
            env={"PATH": str(self.root / "no-programs"), "HOME": str(self.root),
                 "PFV": "/var/tmp/pfv-not-a-layout-probe", "XDG_RUNTIME_DIR": str(self.root / "run")},
            capture_output=True, text=True, timeout=10, check=False,
        )
        self.assertEqual(result.returncode, 64, result.stderr)
        self.assertIn("Refusing a non-private", result.stderr)
        self.assertFalse((self.root / "mixed-before.json").exists())


class MixedLifetimeSnapshotTests(unittest.TestCase):
    def run_snapshot(self, fault=None, *, phase="online"):
        epoch = "a" * 32
        query = {"consumer": "replacement", "request": 2, "intent": "query", "outputName": "Virtual-0"}
        packet = {
            "consumer": "replacement", "request": 2, "epoch": epoch, "revision": 7,
            "status": "online", "capable": True, "backendOwner": ":1.0",
            "identityName": "org.plasmafusion.LayoutProbe.p" + epoch,
            "targetContext": {"epoch": epoch, "generation": 7, "desktopId": "desktop",
                              "activityId": "activity", "outputName": "Virtual-0",
                              "consumerLease": epoch + ":1"},
        }
        unknown = {"boot": "replacement", "phase": "unknown", "request": 2,
                   "packet": None, "accepted": 0, "epoch": "", "revision": -1}
        online = unknown | {
            "phase": "online", "packet": packet, "epoch": epoch, "revision": 7, "accepted": 1,
        }
        events = [("observation", unknown), ("query", {"boot": "replacement", "request": 2}),
                  ("received", packet | {"receiverBoot": "replacement"}), ("observation", online)]
        if fault == "not-accepted":
            events.pop()
        elif fault == "unknown-current":
            events = events[:2]
        elif fault == "newer-query":
            query["request"] = 3
        elif fault == "missing-context":
            query["outputName"] = ""
            packet["targetContext"] = None
        elif fault == "duplicate-native-id":
            pass
        with tempfile.TemporaryDirectory(prefix="pf-mixed-memory-") as scratch:
            root = Path(scratch)
            inventory = [{"id": 8, "request": query, "response": packet}]
            if fault == "duplicate-native-id":
                inventory.append(dict(inventory[0]))
            (root / "inventory.json").write_text(json.dumps(inventory))
            trace = "".join(f"qml: layout-probe-{kind} {json.dumps(row)}\n" for kind, row in events)
            # A half-written next observation must not become part of the saved evidence boundary.
            (root / "plasmashell.log").write_text(trace + 'qml: layout-probe-observation {"boot":')
            (root / "kwin.log").write_text("")
            return subprocess.run(
                [sys.executable, str(MIXED), "snapshot", str(root),
                 str(root / "inventory.json"), phase, str(len(inventory))],
                capture_output=True, text=True, timeout=10, check=False,
            )

    def test_snapshot_correlates_native_inventory_and_accepted_memory_not_saved_response(self):
        result = self.run_snapshot()
        self.assertEqual(result.returncode, 0, result.stderr)
        snapshot = json.loads(result.stdout)
        self.assertEqual(snapshot["shellLines"], 4)
        self.assertEqual(snapshot["widgets"][0]["id"], 8)
        self.assertEqual(snapshot["widgets"][0]["observation"]["packet"]["revision"], 7)

    def test_received_or_saved_response_cannot_substitute_for_online_memory(self):
        result = self.run_snapshot("not-accepted")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("online memory", result.stderr)

    def test_snapshot_cannot_borrow_an_old_generation_for_the_current_native_query(self):
        result = self.run_snapshot("newer-query")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("current query", result.stderr)

    def test_native_widget_ids_must_be_unique(self):
        result = self.run_snapshot("duplicate-native-id")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unique", result.stderr)

    def test_unknown_memory_precedes_its_deferred_fresh_query_after_provider_loss(self):
        result = self.run_snapshot("unknown-current", phase="unknown")
        self.assertEqual(result.returncode, 0, result.stderr)
        current = json.loads(result.stdout)["widgets"][0]["observation"]
        self.assertEqual(current["request"], 2)
        self.assertIsNone(current["packet"])

    def test_online_before_output_attachment_cannot_certify_current_target_context(self):
        result = self.run_snapshot("missing-context")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("target context", result.stderr)


class MixedLifetimePublicationTests(unittest.TestCase):
    def run_publication(self, enabled):
        epoch = "b" * 32
        probe = {"epoch": epoch, "revision": 0, "capable": True, "refusal": -1,
                 "selfOwner": ":1.0", "identityName": "org.plasmafusion.LayoutProbe.p" + epoch,
                 "competingProviderRejected": True, "targetProbe": False,
                 "mixedLifetimeProbe": enabled}
        script = "const probe=" + json.dumps(probe) + ";\n"
        script += """
const records=[];
console.info=(name,text)=>{if(name==='layout-probe-published')records.push(JSON.parse(text));};
const writer={arguments:[],call:()=>{}};
const publish=(function(){with(probe){return METHOD;}})();
publish('online',[{id:8,consumer:'survivor',request:4},
                  {id:9,consumer:'replacement',request:2}],':1.20');
const text=writer.arguments[0];
const messages=JSON.parse(text.slice('var messages = '.length,text.indexOf(';var written=0;')));
process.stdout.write(JSON.stringify({records,packets:messages.map(row=>JSON.parse(row.packet))}));
""".replace("METHOD", qml_handler("publish", "provider.qml"))
        result = subprocess.run(["node", "-"], input=script, capture_output=True, text=True,
                                timeout=10, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_mixed_publication_trace_binds_the_native_row_without_changing_the_packet(self):
        result = self.run_publication(True)
        expected = []
        for identifier, packet in zip((8, 9), result["packets"], strict=True):
            expected.append({key: packet[key] for key in
                             ("consumer", "request", "epoch", "revision", "status")} | {
                                 "widget": identifier, "destination": ":1.20",
                             })
            self.assertNotIn("widget", packet)
            self.assertNotIn("destination", packet)
        self.assertEqual(result["records"], expected)

    def test_other_profiles_keep_the_trace_off_and_the_wire_packets_identical(self):
        disabled, enabled = self.run_publication(False), self.run_publication(True)
        self.assertEqual(disabled["records"], [])
        self.assertEqual(disabled["packets"], enabled["packets"])


class MixedLifetimeReceiptTests(unittest.TestCase):
    def fixture(self, root, *, survivor_lease_changed=False, replacement_retry=False,
                unsolicited_prepare=False, early_recovery=False, defer_recovery=None):
        write_cleanup_fixture(root)
        old, new = "a" * 32, "b" * 32
        shell, backend, live, accepted = [], [], {}, {}

        def emit(kind, row):
            shell.append(f"qml: layout-probe-{kind} {json.dumps(row)}\n")

        def query(boot, request, intent="query", epoch="", lease=""):
            body = {"consumer": boot, "request": request, "version": 1, "intent": intent,
                    "outputName": "Virtual-0", "token": "", "viewEpoch": epoch,
                    "viewGeneration": 7 if epoch else -1, "desktopId": "desktop",
                    "activityId": "activity", "viewOutputName": "Virtual-0",
                    "consumerLease": lease}
            emit("observation", {"boot": boot, "request": request, "phase": "unknown",
                                "packet": None, "accepted": accepted.get(boot, 0),
                                "epoch": "", "revision": -1})
            emit("query", {"boot": boot, "request": request, "deadlineMs": 10000})
            return body

        def packet(body, epoch, revision, lease, preparation=None):
            return {"consumer": body["consumer"], "request": body["request"], "epoch": epoch,
                    "revision": revision, "backendOwner": ":1.0",
                    "identityName": "org.plasmafusion.LayoutProbe.p" + epoch,
                    "status": "online", "capable": True, "preparation": preparation,
                    "targetContext": {"epoch": epoch, "generation": 7, "desktopId": "desktop",
                                      "activityId": "activity", "outputName": "Virtual-0",
                                      "consumerLease": lease}}

        def verdict(value):
            preparation = value["preparation"]
            backend.append("qml: layout-probe-target " + json.dumps({
                "consumer": value["consumer"], "request": value["request"],
                "revision": value["revision"], "intent": preparation["intent"],
                "ready": preparation["ready"], "reason": preparation["reason"],
                "targetAlive": preparation["ready"],
                "targetClass": "pf.focus.alpha" if preparation["ready"] else "",
            }) + "\n")

        def published(identifier, value):
            backend.append("qml: layout-probe-published " + json.dumps({
                "widget": identifier, "destination": ":1.20", "consumer": value["consumer"],
                "request": value["request"], "epoch": value["epoch"],
                "revision": value["revision"], "status": value["status"],
            }) + "\n")

        def online(identifier, body, epoch, revision, lease, preparation=None):
            value = packet(body, epoch, revision, lease, preparation)
            if preparation:
                verdict(value)
            published(identifier, value)
            emit("received", value | {"receiverBoot": body["consumer"]})
            accepted[body["consumer"]] = accepted.get(body["consumer"], 0) + 1
            observation = {"boot": body["consumer"], "request": body["request"], "phase": "online",
                           "packet": value, "accepted": accepted[body["consumer"]],
                           "epoch": epoch, "revision": revision}
            emit("observation", observation)
            live[identifier] = {"id": identifier, "request": body}
            return observation

        def save(name, value):
            (root / name).write_text(json.dumps(value))

        def capture(label, identifiers, phase="online"):
            (root / "plasmashell.log").write_text("".join(shell))
            (root / "kwin.log").write_text("".join(backend))
            inventory = root / f"mixed-{label}-inventory.json"
            save(inventory.name, [live[identifier] for identifier in identifiers])
            value = snapshot(root, inventory, phase, len(identifiers))
            save(f"mixed-{label}.json", value)
            return value

        prepared = {"intent": "prepare", "ready": True, "reason": "", "token": old + ":1"}
        retired = online(7, query("retired", 2, "prepare", old, old + ":1"), old, 2, old + ":1", prepared)
        save("mixed-retired-preparation.json", retired)
        survivor_query = query("survivor", 3, "prepare", old, old + ":2")
        survivor = online(8, survivor_query, old, 4, old + ":2", prepared | {"token": old + ":2"})
        save("consumer-explicit-recovery.json", survivor)
        save("consumer-removed.json", {"removedId": 7, "consumer": "retired"})
        capture("before", [8])
        online(9, query("replacement", 1), old, 6, old + ":3")
        if survivor_lease_changed:
            online(8, survivor_query, old, 7, old + ":4",
                   {"intent": "prepare", "ready": False, "reason": "consumer-not-current", "token": ""})
        save("mixed-created.json", {"id": 9, "survivorId": 8, "panelId": 2})
        capture("consumers", [8, 9])
        if replacement_retry:
            query("survivor", 4)
        survivor_fresh = query("survivor", 5 if replacement_retry else 4)
        replacement_fresh = query("replacement", 2)
        live[8]["request"], live[9]["request"] = survivor_fresh, replacement_fresh
        capture("unknown", [8, 9], "unknown")
        if unsolicited_prepare:
            verdict(packet(survivor_fresh, new, 1, new + ":1",
                           prepared | {"token": new + ":1"}))
        online(8, survivor_fresh, new, 1, new + ":1")
        online(9, replacement_fresh, new, 2, new + ":2")
        capture("reloaded", [8, 9])
        frames = [
            {"kind": "retained-consumer", "id": 9, "receiver": "replacement", "packet": retired["packet"]},
            {"kind": "retired-consumer-fence", "id": 9, "receiver": "replacement",
             "packet": retired["packet"] | {
                 "request": 2, "epoch": new, "identityName": "org.plasmafusion.LayoutProbe.p" + new,
                 "revision": 1002}},
            {"kind": "retired-provider-fence", "id": 8, "receiver": "survivor",
             "packet": survivor["packet"] | {"request": survivor_fresh["request"], "revision": 2001}},
        ]
        save("mixed-frames.json", frames)
        for frame in frames:
            emit("received", frame["packet"] | {"receiverBoot": frame["receiver"]})
        online(8, survivor_fresh, new, 3, new + ":1")
        online(9, replacement_fresh, new, 4, new + ":2")
        capture("after-late", [8, 9])
        save("mixed-replayed-request.json", survivor_query)
        deferred = []
        if early_recovery:
            begin = len(shell)
            online(8, survivor_fresh, new, 6, new + ":1")
            online(9, replacement_fresh, new, 7, new + ":2")
            if defer_recovery:
                immediate = []
                for line in shell[begin:]:
                    if ("layout-probe-observation " in line
                            or (defer_recovery == "delivery" and "layout-probe-received " in line)):
                        deferred.append(line)
                    else:
                        immediate.append(line)
                shell[begin:] = immediate
        refused = {"intent": "prepare", "ready": False, "reason": "consumer-not-current", "token": ""}
        replay = packet(survivor_query, new, 8 if early_recovery else 5, new + ":1", refused)
        verdict(replay)
        published(8, replay)
        emit("received", replay | {"receiverBoot": "survivor"})
        save("mixed-restored-boundary.json", {
            "schema": 1, "shellLines": len(shell), "kwinLines": len(backend),
        })
        shell.extend(deferred)
        if not early_recovery:
            online(8, survivor_fresh, new, 6, new + ":1")
            online(9, replacement_fresh, new, 7, new + ":2")
        capture("after-replay", [8, 9])
        emit("keyboard-query", {"boot": "replacement", "request": 3, "intent": "prepare",
                                "activeFocus": True, "key": 32, "screen": "Virtual-0"})
        fresh = query("replacement", 3, "prepare", new, new + ":2")
        online(9, fresh, new, 9 if early_recovery else 8, new + ":2", prepared | {"token": new + ":1"})
        capture("final", [8, 9])
        save("mixed-owners.json", {
            "busBefore": "a" * 32, "busAfter": "a" * 32,
            "backendBefore": ":1.0", "backendAfter": ":1.0",
            "shellBefore": ":1.20", "shellAfter": ":1.20",
            "retiredIdentity": "org.plasmafusion.LayoutProbe.p" + old, "retiredHeld": False,
            "newIdentity": "org.plasmafusion.LayoutProbe.p" + new, "newOwner": ":1.0",
        })
        save("mixed-lifetime-result.json", {
            "schema": 1, "passed": True,
            "checks": ["roundtrip-native", "consumer-replacement", "provider-reload",
                       "late-frame-rejection", "stale-intent-refusal", "explicit-recovery"],
        })
        (root / "scenario.log").write_text("scenario rc=0\nsession rc=0\n")

    def run_check(self, fault=None, *, survivor_lease_changed=False, replacement_retry=False,
                  unsolicited_prepare=False, early_recovery=False, defer_recovery=None):
        with tempfile.TemporaryDirectory(prefix="pf-mixed-check-") as scratch:
            root = Path(scratch)
            self.fixture(root, survivor_lease_changed=survivor_lease_changed,
                         replacement_retry=replacement_retry, unsolicited_prepare=unsolicited_prepare,
                         early_recovery=early_recovery, defer_recovery=defer_recovery)
            if fault:
                fault(root)
            return subprocess.run(
                [sys.executable, str(PREPARER), "--check-result", str(root),
                 "--scope", "mixed-lifetimes"],
                capture_output=True, text=True, timeout=10, check=False,
            )

    def test_combined_scope_requires_correlated_raw_evidence_and_clean_teardown(self):
        result = self.run_check()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_final_snapshot_cannot_drop_the_surviving_consumer(self):
        def drop_survivor(root):
            for name in ("mixed-final.json", "mixed-final-inventory.json"):
                path = root / name
                value = json.loads(path.read_text())
                rows = value if isinstance(value, list) else value["widgets"]
                rows[:] = [row for row in rows if row["id"] != 8]
                path.write_text(json.dumps(value))

        result = self.run_check(drop_survivor)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("final inventory lost or replaced a live consumer", result.stderr)

    def test_scope_does_not_accept_only_a_success_flag(self):
        result = self.run_check(lambda root: (root / "mixed-reloaded.json").unlink())
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("mixed-reloaded.json", result.stderr)

    def test_complete_mixed_functionality_cannot_hide_missing_cleanup(self):
        result = self.run_check(lambda root: (root / "cleanup-result.json").unlink())
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("cleanup", result.stderr)

    def test_native_preparation_verdict_must_name_the_intended_live_application(self):
        def redirect(root):
            path = root / "kwin.log"
            path.write_text(path.read_text().replace("pf.focus.alpha", "pf.focus.beta"))
        result = self.run_check(redirect)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("native verdict", result.stderr)

    def test_provider_reload_cannot_be_certified_on_a_replaced_backend(self):
        def replace_owner(root):
            path = root / "mixed-owners.json"
            owner = json.loads(path.read_text())
            owner["backendAfter"] = ":1.99"
            path.write_text(json.dumps(owner))
        result = self.run_check(replace_owner)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("bus/backend/shell", result.stderr)

    def test_late_frames_must_actually_reach_their_claimed_live_receivers(self):
        def missing_frame(root):
            path = root / "mixed-frames.json"
            frames = json.loads(path.read_text())
            path.write_text(json.dumps(frames[:-1]))
        self.assertNotEqual(self.run_check(missing_frame).returncode, 0)

    def test_late_received_frames_cannot_become_accepted_stale_state_later(self):
        def stale_acceptance(root):
            row = json.loads((root / "consumer-explicit-recovery.json").read_text())
            row["request"] = row["packet"]["request"] = 4
            row["revision"] = row["packet"]["revision"] = 2001
            with (root / "plasmashell.log").open("a") as output:
                output.write("qml: layout-probe-observation " + json.dumps(row) + "\n")
        self.assertNotEqual(self.run_check(stale_acceptance).returncode, 0)

    def test_late_rejection_needs_a_later_genuine_response_not_an_unchanged_snapshot(self):
        def no_drain(root):
            for suffix in (".json", "-inventory.json"):
                (root / ("mixed-after-late" + suffix)).write_bytes(
                    (root / ("mixed-reloaded" + suffix)).read_bytes()
                )
        self.assertNotEqual(self.run_check(no_drain).returncode, 0)

    def test_no_automatic_query_retry_is_hidden_after_provider_recovery(self):
        def retry(root):
            with (root / "plasmashell.log").open("a") as output:
                output.write('qml: layout-probe-query {"boot":"survivor","request":5}\n')
        self.assertNotEqual(self.run_check(retry).returncode, 0)

    def test_the_old_prepare_replay_requires_its_exact_native_refusal(self):
        def accepted_replay(root):
            path = root / "kwin.log"
            lines = path.read_text().splitlines()
            for index, line in enumerate(lines):
                marker = "layout-probe-target "
                if marker not in line:
                    continue
                row = json.loads(line.split(marker, 1)[1])
                if row["consumer"] == "survivor" and row["revision"] == 5:
                    row.update(ready=True, reason="", targetAlive=True, targetClass="pf.focus.alpha")
                    lines[index] = "qml: " + marker + json.dumps(row)
            path.write_text("\n".join(lines) + "\n")
        self.assertNotEqual(self.run_check(accepted_replay).returncode, 0)

    def test_a_new_consumer_cannot_reuse_the_retired_consumers_public_lease(self):
        def reused_lease(root):
            before, after = "a" * 32 + ":3", "a" * 32 + ":1"
            for name in ("mixed-consumers.json", "plasmashell.log"):
                path = root / name
                path.write_text(path.read_text().replace(before, after))
        self.assertNotEqual(self.run_check(reused_lease).returncode, 0)

    def test_provider_replacement_cannot_reuse_the_new_consumers_previous_provider_lease(self):
        def reused_lease(root):
            before, after = "b" * 32 + ":2", "a" * 32 + ":3"
            for path in [*root.glob("*.json"), root / "plasmashell.log"]:
                path.write_text(path.read_text().replace(before, after))
        self.assertNotEqual(self.run_check(reused_lease).returncode, 0)

    def test_replacing_an_unrelated_consumer_cannot_reissue_the_survivors_lease(self):
        self.assertNotEqual(self.run_check(survivor_lease_changed=True).returncode, 0)

    def test_recovery_requires_actual_explicit_input_not_only_a_successful_preparation(self):
        def missing_input(root):
            path = root / "plasmashell.log"
            path.write_text(path.read_text().replace("layout-probe-keyboard-query ",
                                                     "layout-probe-unrelated-input "))
        self.assertNotEqual(self.run_check(missing_input).returncode, 0)

    def test_every_late_frame_needs_actual_delivery_not_only_an_injection_record(self):
        def missing_delivery(root):
            path = root / "plasmashell.log"
            lines = path.read_text().splitlines(keepends=True)
            for index, line in enumerate(lines):
                marker = "layout-probe-received "
                if marker in line and json.loads(line.split(marker, 1)[1])["revision"] == 1002:
                    lines[index] = line.replace(marker, "layout-probe-not-delivered ")
            path.write_text("".join(lines))
        self.assertNotEqual(self.run_check(missing_delivery).returncode, 0)

    def test_a_newer_response_before_the_last_late_frame_cannot_prove_the_queue_drained(self):
        def reversed_delivery(root):
            path = root / "plasmashell.log"
            lines = path.read_text().splitlines(keepends=True)
            before = json.loads((root / "mixed-reloaded.json").read_text())["shellLines"]
            after = json.loads((root / "mixed-after-late.json").read_text())["shellLines"]
            frames = json.loads((root / "mixed-frames.json").read_text())
            received = [frame["packet"] | {"receiverBoot": frame["receiver"]} for frame in frames]
            late, other = [], []
            for line in lines[before:after]:
                marker = "layout-probe-received "
                if marker in line and json.loads(line.split(marker, 1)[1]) in received:
                    late.append(line)
                else:
                    other.append(line)
            self.assertEqual(len(late), 3)
            path.write_text("".join(lines[:before] + other + late + lines[after:]))
        self.assertNotEqual(self.run_check(reversed_delivery).returncode, 0)

    def test_a_response_received_before_the_late_frame_cannot_prove_the_drain(self):
        def early_receipt(root):
            # The survivor's revision 3 arrived before its late frame and was verified after it,
            # while the late frame waited in the pending slot.
            path = root / "plasmashell.log"
            lines = path.read_text().splitlines(keepends=True)
            marker = "layout-probe-received "

            def revision(line):
                return json.loads(line.split(marker, 1)[1])["revision"] if marker in line else None
            genuine = next(index for index, line in enumerate(lines) if revision(line) == 3)
            late = next(index for index, line in enumerate(lines) if revision(line) == 2001)
            lines.insert(late, lines.pop(genuine))
            path.write_text("".join(lines))
        result = self.run_check(early_receipt)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("missing genuine response after the late-frame drain", result.stderr)

    def test_the_late_frame_drain_needs_its_exact_native_publication(self):
        def missing_publication(root):
            path = root / "kwin.log"
            marker = "layout-probe-published "
            lines = [line.replace(marker, "layout-probe-not-published ")
                     if marker in line and json.loads(line.split(marker, 1)[1])["revision"] == 3
                     else line for line in path.read_text().splitlines(keepends=True)]
            path.write_text("".join(lines))
        result = self.run_check(missing_publication)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("late-frame drain lacks its exact native publication", result.stderr)

    def test_a_publication_before_the_reload_cannot_stand_for_the_drains(self):
        def early_publication(root):
            path = root / "kwin.log"
            lines = path.read_text().splitlines(keepends=True)
            marker = "layout-probe-published "
            reloaded = json.loads((root / "mixed-reloaded.json").read_text())["kwinLines"]
            genuine = next(index for index, line in enumerate(lines) if marker in line
                           and json.loads(line.split(marker, 1)[1])["revision"] == 3)
            lines.insert(reloaded - 1, lines.pop(genuine))
            path.write_text("".join(lines))
        result = self.run_check(early_publication)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("late-frame drain lacks its exact native publication", result.stderr)

    def test_the_drains_response_must_be_received_before_it_was_accepted(self):
        def receipt_after_acceptance(root):
            path = root / "plasmashell.log"
            lines = path.read_text().splitlines(keepends=True)

            def revision(line, kind):
                marker = f"layout-probe-{kind} "
                return json.loads(line.split(marker, 1)[1])["revision"] if marker in line else None
            genuine = next(index for index, line in enumerate(lines)
                           if revision(line, "received") == 3)
            accepted = next(index for index, line in enumerate(lines)
                            if revision(line, "observation") == 3)
            # Popping the earlier receipt moves the acceptance up one line: insert after it.
            lines.insert(accepted, lines.pop(genuine))
            path.write_text("".join(lines))
        result = self.run_check(receipt_after_acceptance)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("missing genuine response after the late-frame drain", result.stderr)

    def test_transient_acceptance_of_the_replayed_obsolete_request_is_not_hidden_by_recovery(self):
        def stale_request(root):
            path = root / "plasmashell.log"
            lines = path.read_text().splitlines(keepends=True)
            current = json.loads((root / "mixed-after-late.json").read_text())["widgets"][0]["observation"]
            marker = "layout-probe-received "
            index, packet = next(
                (index, json.loads(line.split(marker, 1)[1]))
                for index, line in enumerate(lines) if marker in line
                and (json.loads(line.split(marker, 1)[1]).get("preparation") or {}).get("reason")
                == "consumer-not-current"
            )
            packet.pop("receiverBoot")
            stale = current | {"packet": packet, "revision": packet["revision"],
                               "accepted": current["accepted"] + 1}
            inserted = index + 1
            lines.insert(inserted, "qml: layout-probe-observation " + json.dumps(stale) + "\n")
            for offset in range(inserted + 1, len(lines)):
                if "layout-probe-observation " in lines[offset]:
                    row = json.loads(lines[offset].split("layout-probe-observation ", 1)[1])
                    if row["boot"] == current["boot"]:
                        row["accepted"] += 1
                        lines[offset] = "qml: layout-probe-observation " + json.dumps(row) + "\n"
            path.write_text("".join(lines))
            for saved in root.glob("*.json"):
                value = json.loads(saved.read_text())
                if isinstance(value, dict) and value.get("shellLines", 0) > inserted:
                    value["shellLines"] += 1
                    for widget in value.get("widgets", []):
                        if widget["observation"]["boot"] == current["boot"]:
                            widget["observation"]["accepted"] += 1
                    saved.write_text(json.dumps(value))
        self.assertNotEqual(self.run_check(stale_request).returncode, 0)

    def test_intermediate_query_retries_during_provider_replacement_are_not_hidden(self):
        self.assertNotEqual(self.run_check(replacement_retry=True).returncode, 0)

    def test_unsolicited_native_preparation_during_provider_replacement_is_not_hidden(self):
        self.assertNotEqual(self.run_check(unsolicited_prepare=True).returncode, 0)

    def test_unknown_provider_loss_memory_must_precede_its_deferred_outbound_query(self):
        def reversed_query(root):
            path = root / "plasmashell.log"
            lines = path.read_text().splitlines(keepends=True)
            positions = {}
            for index, line in enumerate(lines):
                for kind in ("query", "observation"):
                    marker = "layout-probe-" + kind + " "
                    if marker in line:
                        row = json.loads(line.split(marker, 1)[1])
                        if row["boot"] == "survivor" and row["request"] == 4:
                            if kind == "query" or row["phase"] == "unknown":
                                positions.setdefault(kind, index)
            left, right = positions["query"], positions["observation"]
            lines[left], lines[right] = lines[right], lines[left]
            path.write_text("".join(lines))
        self.assertNotEqual(self.run_check(reversed_query).returncode, 0)

    def test_a_response_accepted_before_replay_refusal_and_restoration_is_not_recovery(self):
        self.assertNotEqual(self.run_check(early_recovery=True).returncode, 0)

    def test_pre_restoration_receipt_with_delayed_verification_cannot_be_borrowed(self):
        self.assertNotEqual(self.run_check(
            early_recovery=True, defer_recovery="verification"
        ).returncode, 0)

    def test_pre_restoration_publication_with_late_receipt_cannot_be_borrowed(self):
        self.assertNotEqual(self.run_check(
            early_recovery=True, defer_recovery="delivery"
        ).returncode, 0)

    def test_recovery_requires_the_exact_post_restoration_backend_publication(self):
        def missing_publication(root):
            path = root / "kwin.log"
            lines = path.read_text().splitlines(keepends=True)
            for index, line in enumerate(lines):
                marker = "layout-probe-published "
                if marker in line and json.loads(line.split(marker, 1)[1])["revision"] == 6:
                    lines[index] = line.replace(marker, "layout-probe-not-published ")
            path.write_text("".join(lines))
        self.assertNotEqual(self.run_check(missing_publication).returncode, 0)

    def test_recovery_cannot_qualify_without_its_post_restoration_boundary(self):
        self.assertNotEqual(self.run_check(
            lambda root: (root / "mixed-restored-boundary.json").unlink()
        ).returncode, 0)

    def test_restoration_boundary_cannot_be_silently_replaced_by_a_later_attempt(self):
        with tempfile.TemporaryDirectory(prefix="pf-mixed-boundary-") as scratch:
            root = Path(scratch)
            self.fixture(root)
            path = root / "mixed-restored-boundary.json"
            original = path.read_bytes()
            result = subprocess.run(
                [sys.executable, str(MIXED), "restored", str(root)],
                capture_output=True, text=True, timeout=10, check=False,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("exists", result.stderr)
            self.assertEqual(path.read_bytes(), original)

    def test_generated_frames_write_only_the_captured_current_widget_lifetimes(self):
        with tempfile.TemporaryDirectory(prefix="pf-mixed-frame-") as scratch:
            root = Path(scratch)
            self.fixture(root)
            expected = json.loads((root / "mixed-frames.json").read_text())
            (root / "mixed-frames.json").unlink()
            result = subprocess.run(
                [sys.executable, str(MIXED), "frames", str(root)],
                capture_output=True, text=True, timeout=10, check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads((root / "mixed-frames.json").read_text()), expected)
            current = json.loads((root / "mixed-reloaded-inventory.json").read_text())
            script = "const current=" + json.dumps(current) + ";\n" + """
const writes=[],counts=[];
const print=value=>counts.push(value);
const controls=current.map(row=>({
    id:row.id,readConfig:()=>JSON.stringify(row.request),
    writeConfig:(name,value)=>{if(name!=='layoutResponse')throw Error(name);
                             writes.push({id:row.id,packet:JSON.parse(value)});}
}));
const panels=()=>[{widgets:()=>controls}];
""" + (root / "mixed-inject.js").read_text()
            script += "\nprocess.stdout.write(JSON.stringify({writes,counts}));\n"
            result = subprocess.run(["node", "-"], input=script, capture_output=True, text=True,
                                    timeout=10, check=False)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(result.stdout), {
                "writes": [{"id": row["id"], "packet": row["packet"]} for row in expected],
                "counts": [3],
            })

    def test_frame_generation_never_overwrites_a_previous_injection_record(self):
        with tempfile.TemporaryDirectory(prefix="pf-mixed-frame-") as scratch:
            root = Path(scratch)
            self.fixture(root)
            previous = (root / "mixed-frames.json").read_bytes()
            result = subprocess.run(
                [sys.executable, str(MIXED), "frames", str(root)],
                capture_output=True, text=True, timeout=10, check=False,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("exists", result.stderr)
            self.assertEqual((root / "mixed-frames.json").read_bytes(), previous)

    def test_runtime_partial_checks_and_final_scope_use_the_same_raw_qualifier(self):
        with tempfile.TemporaryDirectory(prefix="pf-mixed-runtime-") as scratch:
            root = Path(scratch)
            self.fixture(root)
            for mode in ("late", "refusal", "progress", "check"):
                with self.subTest(mode=mode):
                    result = subprocess.run(
                        [sys.executable, str(MIXED), mode, str(root)],
                        capture_output=True, text=True, timeout=10, check=False,
                    )
                    self.assertEqual(result.returncode, 0, result.stderr)
