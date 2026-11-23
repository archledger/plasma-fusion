# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Activity/output-loss probe cases, re-exported by the existing test entry point."""

import hashlib
import json
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

if __package__:
    from . import view_loss
    from .cleanup_tests import write_cleanup_fixture
    from .qml_helpers import qml_handler
else:
    import view_loss
    from cleanup_tests import write_cleanup_fixture
    from qml_helpers import qml_handler

PREPARER = Path(__file__).with_name("prepare_seed.py")
VIEW = Path(__file__).with_name("view_loss.py")
PROVIDER = Path(__file__).with_name("provider.qml")
RULES = (Path(__file__).resolve().parents[3]
         / "packages/kwin/scripts/plasmafusion-placement/contents/ui/Tiling.js")
APP = "pf.focus.alpha"


def block_function(source: str, start: int) -> str:
    opening = source.index("{", start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


def connections_handler(target: str, name: str) -> str:
    """One handler from the Connections block bound to this exact target."""
    source = PROVIDER.read_text()
    binding = source.index(f"target: {target}\n")
    start = source.rindex("Connections {", 0, binding)
    # Search only that block: a handler moved elsewhere is not connected to this target.
    block = block_function(source, start)
    return block_function(block, block.index(f"function {name}(", binding - start))


class ViewLossSeedTests(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory(prefix="pf-view-seed-")
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

    def test_view_loss_probe_is_explicit_and_reuses_the_private_target_controls(self):
        result = self.run_seed("--view-loss-probe")
        self.assertEqual(result.returncode, 0, result.stderr)
        config = (self.output / ".config/kwinrc").read_text()
        for setting in ("ViewLossProbe=true", "TargetProbe=true", "FocusProbe=true",
                        "MixedLifetimeProbe=false", "DropRetirementFrame=false", "ReplyDelayMs=0"):
            self.assertIn(setting, config)
        manifest = json.loads((self.output / "probe-inputs.json").read_text())
        for helper in ("heldclient.py", "receipts.py", "cleanup.py"):
            self.assertIn(helper, manifest)

    def test_normal_and_mixed_seeds_keep_the_view_loss_case_off(self):
        for arguments in ((), ("--mixed-lifetime-probe",)):
            with self.subTest(arguments=arguments):
                result = self.run_seed(*arguments)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("ViewLossProbe=false", (self.output / ".config/kwinrc").read_text())
                manifest = json.loads((self.output / "probe-inputs.json").read_text())
                for helper in ("view_loss.py", "view_loss_scenario.sh"):
                    self.assertNotIn(helper, manifest)
                    self.assertFalse((self.output / ".local/lib/layout-control" / helper).exists())
                shutil.rmtree(self.output)

    def test_view_loss_seed_copies_and_hashes_its_case_checker_and_shared_reader(self):
        result = self.run_seed("--view-loss-probe")
        self.assertEqual(result.returncode, 0, result.stderr)
        manifest = json.loads((self.output / "probe-inputs.json").read_text())
        for helper in ("view_loss.py", "view_loss_scenario.sh", "mixed_lifetime.py"):
            copied = self.output / ".local/lib/layout-control" / helper
            self.assertEqual(copied.read_bytes(), VIEW.with_name(helper).read_bytes())
            self.assertEqual(manifest[helper], hashlib.sha256(copied.read_bytes()).hexdigest())
        # The mixed case is not sourced by this mode; only its complete-line reader is reused.
        self.assertNotIn("mixed_scenario.sh", manifest)
        self.assertFalse((self.output / ".local/lib/layout-control/mixed_scenario.sh").exists())

    def test_view_loss_and_mixed_lifetime_cases_cannot_stack(self):
        result = self.run_seed("--view-loss-probe", "--mixed-lifetime-probe")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("separate private cases", result.stderr)
        self.assertFalse(self.output.exists())

    def test_view_loss_mode_rejects_transport_faults_before_creating_a_seed(self):
        for fault in (("--drop-retirement-frame",),
                      ("--query-timeout-ms", "200", "--reply-delay-ms", "2000")):
            with self.subTest(fault=fault):
                result = self.run_seed("--view-loss-probe", *fault)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("requires normal transport", result.stderr)
                self.assertFalse(self.output.exists())

    def test_result_check_cannot_enable_the_view_loss_seed_mode(self):
        result = subprocess.run(
            [sys.executable, str(PREPARER), "--check-result", str(self.output),
             "--view-loss-probe"],
            cwd=self.root, capture_output=True, text=True, timeout=10, check=False,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("--check-result cannot be combined", result.stderr)

    @unittest.skipIf(Path("/run/.containerenv").exists(), "the test host is a container")
    def test_sourced_view_case_requires_an_actual_container(self):
        private = "/var/tmp/pfv-layout-control-unit"
        result = subprocess.run(
            ["/usr/bin/bash", "-c", 'source "$1"', "view-case",
             str(VIEW.with_name("view_loss_scenario.sh"))],
            env={"PATH": str(self.root / "no-programs"), "HOME": private + "/home",
                 "PFV": private, "XDG_RUNTIME_DIR": private + "/run",
                 "PF_LAYOUT_PRIVATE_CONTAINER": "1"},
            capture_output=True, text=True, timeout=10, check=False,
        )
        self.assertEqual(result.returncode, 64, result.stderr)
        self.assertIn("Refusing a non-private", result.stderr)

    def test_sourced_view_case_refuses_non_private_context_before_any_helper(self):
        result = subprocess.run(
            ["/usr/bin/bash", "-c", 'source "$1"', "view-case",
             str(VIEW.with_name("view_loss_scenario.sh"))],
            env={"PATH": str(self.root / "no-programs"), "HOME": str(self.root),
                 "PFV": "/var/tmp/pfv-not-a-layout-probe",
                 "XDG_RUNTIME_DIR": str(self.root / "run")},
            capture_output=True, text=True, timeout=10, check=False,
        )
        self.assertEqual(result.returncode, 64, result.stderr)
        self.assertIn("Refusing a non-private", result.stderr)
        self.assertFalse(list(self.root.glob("view-*")))


class ViewLossTraceTests(unittest.TestCase):
    METHODS = ("shellOwnsFocus", "invalidateTarget", "targetContextReady", "targetViewIsCurrent",
               "prepareTarget", "validateTarget", "trackTargetActivation", "targetViewChanged",
               "targetMembershipChanged", "advanceTargetContext", "captureTargetContext",
               "targetEligibilityChanged", "canUseTargetHandoff", "traceView")

    def run_trace(self, action, *, enabled=True, handlers=(), requests=False):
        script = r"""
const vm = require('node:vm');
const Tiling = {};
vm.runInNewContext(RULES.replace(/^\.pragma library$/m, ''), Tiling);
const output = {name:'Virtual-0', geometry:{x:0,y:0,width:1440,height:900}};
const otherOutput = {name:'Virtual-1', geometry:{x:1440,y:0,width:1440,height:900}};
const desktop = {id:'desktop-a'}, otherDesktop = {id:'desktop-b'};
let currentDesktop = desktop;
const Workspace = {
    screens:[output, otherOutput], desktops:[desktop, otherDesktop],
    activities:['activity-a'], currentActivity:'activity-a', currentDesktop:desktop,
    currentDesktopForScreen:()=>currentDesktop, activeWindow:null
};
const app = {
    deleted:false, normalWindow:true, transient:false, modal:false, moveable:true, resizeable:true,
    fullScreen:false, tile:null, minimized:false, maximizeMode:0, skipTaskbar:false,
    skipSwitcher:false, desktops:[desktop], activities:['activity-a'], output:output, pid:101,
    resourceClass:'pf.focus.alpha', frameGeometry:{x:505,y:292,width:430,height:310}
};
const panel = {
    deleted:false, normalWindow:false, appletPopup:true, dock:false, desktopWindow:false,
    output:output, pid:202, resourceClass:'plasmashell'
};
const records = [];
console.info = (name, text) => {
    if (name === 'layout-probe-view') records.push(JSON.parse(text));
};
const probe = {
    authorized:true, capable:true, identityReady:true, stopping:false, readOwner:':1.20',
    shellPid:202, shellPidOwner:':1.20', lastEligibleWindow:app, preparedTarget:null,
    preparationFailure:'not-prepared', epoch:'a'.repeat(32), targetExchange:null, targetSerial:0,
    targetGeneration:0, lastFocusedWindow:panel, targetHandoff:null, targetConsumers:[],
    consumerSerial:0, inventoryOwner:'', targetInventoryComplete:false, targetProbe:true,
    viewLossProbe:ENABLED, viewLossSubject:app, viewLossScreens:[output, otherOutput],
    traceFocus:()=>{}, scan:()=>{}
};
Workspace.activeWindow = panel;
const methods = (function(){with(probe){return {
""".replace("RULES", json.dumps(RULES.read_text())).replace("ENABLED", json.dumps(enabled))
        methods = self.METHODS + (("handleTargetRequest", "reconcileTargetConsumers",
                                   "targetConsumerFor") if requests else ())
        script += ",".join(name + ":" + qml_handler(name, "provider.qml") for name in methods)
        script += "};}})();Object.assign(probe,methods);\n"
        script += "".join(handler + ";\n" for handler in handlers)
        script += action
        script += ("\nprocess.stdout.write(JSON.stringify({records,"
                   "generation:probe.targetGeneration,prepared:probe.preparedTarget!==null,"
                   "replies:globalThis.replies||null}));\n")
        result = subprocess.run(["node", "-"], input=script, capture_output=True, text=True,
                                timeout=10, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_every_generation_advance_is_traced_once_with_its_native_source(self):
        result = self.run_trace("""
probe.prepareTarget('Virtual-0');
probe.targetViewChanged('screens');
probe.targetMembershipChanged('window-output');
const other = {...app, pid:303};
Workspace.activeWindow = other;
probe.trackTargetActivation(other);
""")
        rows = result["records"]
        self.assertEqual([(row["reason"], row["source"], row["from"], row["generation"])
                          for row in rows],
                         [("view-changed", "screens", 0, 1),
                          ("target-departed", "window-output", 1, 2),
                          ("focus-changed", "activation", 2, 3)])
        self.assertEqual([row["prepared"] for row in rows], [True, False, False])
        self.assertEqual(result["generation"], 3)
        for row in rows:
            self.assertEqual(set(row), view_loss.VIEW_KEYS)

    def test_checker_fixture_uses_the_provider_reply_shapes(self):
        result = self.run_trace("""
probe.reconcileTargetConsumers({complete:true,widgets:[{id:7,consumer:'current'}]});
const lease=probe.targetConsumerFor(7,'current').lease;
const prepare={version:1,id:7,consumer:'current',request:2,intent:'prepare',consumerLease:lease,
               outputName:'Virtual-0',token:'',viewEpoch:probe.epoch,viewGeneration:0,
               desktopId:'desktop-a',activityId:'activity-a',viewOutputName:'Virtual-0'};
const first=probe.handleTargetRequest(prepare);
const second=probe.handleTargetRequest({...prepare,request:3,intent:'validate',token:first.token});
globalThis.replies=[first, second];
""", requests=True)
        first, second = result["replies"]
        self.assertEqual(first, prepared_reply("a" * 32 + ":1"))
        self.assertEqual(second, VALIDATED)

    def test_view_trace_is_off_outside_the_view_loss_case(self):
        result = self.run_trace(
            "probe.prepareTarget('Virtual-0');probe.targetViewChanged('screens');", enabled=False)
        self.assertEqual(result["records"], [])
        self.assertEqual((result["generation"], result["prepared"]), (1, False))

    def test_workspace_handlers_name_their_own_view_source(self):
        for name, source in (("onCurrentDesktopChanged", "current-desktop"),
                             ("onCurrentActivityChanged", "current-activity"),
                             ("onScreensChanged", "screens"), ("onDesktopsChanged", "desktops"),
                             ("onActivitiesChanged", "activities")):
            with self.subTest(handler=name):
                handler = connections_handler("Workspace", name)
                result = self.run_trace(f"{name}();", handlers=(handler,))
                self.assertEqual([(row["reason"], row["source"]) for row in result["records"]],
                                 [("view-changed", source)])

    def test_a_handler_moved_out_of_its_bound_block_is_not_found(self):
        # Moved to the window's block, onScreensChanged no longer follows Workspace.screens.
        handler = connections_handler("Workspace", "onScreensChanged")
        binding = "target: probe.lastEligibleWindow\n"
        moved = PROVIDER.read_text().replace(handler, "", 1)
        moved = moved.replace(binding, binding + handler + "\n", 1)
        scratch = tempfile.TemporaryDirectory(prefix="pf-view-handler-")
        self.addCleanup(scratch.cleanup)
        copy = Path(scratch.name) / "provider.qml"
        copy.write_text(moved)
        with mock.patch.object(sys.modules[__name__], "PROVIDER", copy):
            with self.assertRaises(ValueError):
                connections_handler("Workspace", "onScreensChanged")

    def test_window_handlers_name_membership_and_eligibility_sources(self):
        for name, setup, source in (
            ("onDesktopsChanged", "", "window-desktops"),
            ("onActivitiesChanged", "", "window-activities"),
            ("onOutputChanged", "", "window-output"),
            ("onMinimizedChanged", "app.minimized=true;", "window-minimized"),
            ("onFullScreenChanged", "app.fullScreen=true;", "window-fullscreen"),
            ("onMaximizedChanged", "app.maximizeMode=3;", "window-maximized"),
            ("onTileChanged", "app.tile={};", "window-tile"),
            ("onSkipTaskbarChanged", "app.skipTaskbar=true;", "window-skip-taskbar"),
            ("onSkipSwitcherChanged", "app.skipSwitcher=true;", "window-skip-switcher"),
            ("onTransientChanged", "app.transient=true;", "window-transient"),
            ("onModalChanged", "app.modal=true;", "window-modal"),
        ):
            with self.subTest(handler=name):
                handler = connections_handler("probe.lastEligibleWindow", name)
                result = self.run_trace(setup + f"{name}();", handlers=(handler,))
                self.assertEqual([(row["reason"], row["source"]) for row in result["records"]],
                                 [("target-departed", source)])

    def test_window_removal_names_its_source_for_target_and_focus_paths(self):
        handler = connections_handler("Workspace", "onWindowRemoved")
        for setup, reason in (("", "target-departed"),
                              ("probe.lastEligibleWindow=null;probe.lastFocusedWindow=app;",
                               "focus-changed")):
            with self.subTest(reason=reason):
                result = self.run_trace(setup + "onWindowRemoved(app);", handlers=(handler,))
                self.assertEqual([(row["reason"], row["source"]) for row in result["records"]],
                                 [(reason, "window-removed")])

    def test_every_provider_invalidation_call_names_a_known_source(self):
        source = PROVIDER.read_text()
        for name in ("targetViewChanged", "targetMembershipChanged", "targetEligibilityChanged",
                     "advanceTargetContext"):
            # Remove pass-through definitions; every remaining call must carry a literal label.
            definition = source.index(f"function {name}(")
            source = source.replace(block_function(source, definition), "")
        labels = re.findall(r"\b(?:targetViewChanged|targetMembershipChanged|"
                            r"targetEligibilityChanged)\(([^)]*)\)", source)
        labels += [arguments.split(",", 1)[1].strip() if "," in arguments else arguments
                   for arguments in re.findall(r"\badvanceTargetContext\(([^)]*)\)", source)]
        self.assertTrue(labels)
        self.assertTrue(all(re.fullmatch(r'"[a-z-]+"', label) for label in labels), labels)
        self.assertEqual({label.strip('"') for label in labels}, view_loss.SOURCES)

    def test_same_name_replacement_is_reported_as_a_new_native_output(self):
        result = self.run_trace("""
const replacement = {name:'Virtual-0', geometry:{x:0,y:0,width:1440,height:900}};
for (const screens of [[otherOutput], [replacement, otherOutput], [output, otherOutput],
                       [replacement, otherOutput]]) {
    Workspace.screens = screens;
    probe.targetViewChanged('screens');
}
""")
        self.assertEqual([[(row["name"], row["known"]) for row in record["screens"]]
                          for record in result["records"]],
                         [[("Virtual-1", True)],
                          [("Virtual-0", False), ("Virtual-1", True)],
                          [("Virtual-0", True), ("Virtual-1", True)],
                          [("Virtual-0", True), ("Virtual-1", True)]])
        self.assertEqual(result["records"][0]["screens"][0],
                         {"name": "Virtual-1", "known": True, "x": 1440, "y": 0,
                          "width": 1440, "height": 900})

    def test_subject_reports_hidden_or_evacuated_membership_without_identity(self):
        result = self.run_trace("""
Workspace.currentActivity = 'activity-b';
Workspace.activities = ['activity-a', 'activity-b'];
probe.targetViewChanged('current-activity');
Workspace.currentActivity = 'activity-a';
app.output = otherOutput;
app.frameGeometry = {x:1945,y:292,width:430,height:310};
Workspace.screens = [otherOutput];
probe.targetViewChanged('screens');
""")
        hidden, evacuated = result["records"]
        self.assertEqual((hidden["subjectClass"], hidden["subjectOutput"], hidden["subjectInView"],
                          hidden["activityId"], hidden["activities"]),
                         (APP, "Virtual-0", False, "activity-b", 2))
        self.assertEqual((evacuated["subjectOutput"], evacuated["subjectInView"],
                          evacuated["subjectFrame"]),
                         ("Virtual-1", True, {"x": 1945, "y": 292, "width": 430, "height": 310}))
        self.assertNotIn("pid", json.dumps(result["records"]))

    def test_decisions_and_packets_never_read_the_diagnostic_view_state(self):
        for name in ("prepareTarget", "validateTarget", "handleTargetRequest",
                     "canUseTargetHandoff", "captureTargetContext", "captureTargetConsumerContext",
                     "targetContextReady", "targetViewIsCurrent", "shellOwnsFocus",
                     "trackTargetActivation", "publish", "consumeTargetInventory",
                     "reconcileTargetConsumers", "invalidateTarget"):
            with self.subTest(method=name):
                body = qml_handler(name, "provider.qml")
                self.assertNotIn("viewLossSubject", body)
                self.assertNotIn("viewLossScreens", body)
        source = PROVIDER.read_text()
        writers = [match.start() for match in re.finditer(r"viewLossSubject = ", source)]
        handler = source.index("function onWindowActivated(")
        self.assertEqual(len(writers), 1)
        self.assertLess(handler, writers[0])
        activation = connections_handler("Workspace", "onWindowActivated")
        self.assertLess(writers[0], handler + len(activation))

    def test_activation_records_the_subject_only_for_eligible_apps_in_this_case(self):
        handler = qml_handler("onWindowActivated", "provider.qml")
        for enabled, window, expected in ((True, "app", True), (True, "panel", False),
                                          (False, "app", False)):
            with self.subTest(enabled=enabled, window=window):
                script = (
                    "const app={eligible:true},panel={eligible:false};"
                    "const Tiling={eligibleForMaster:window=>!!window&&window.eligible};"
                    "const probe={targetProbe:true,viewLossProbe:" + json.dumps(enabled) + ","
                    "viewLossSubject:null,trackTargetActivation:()=>{},traceFocus:()=>{}};"
                    + handler + ";onWindowActivated(" + window + ");"
                    "process.stdout.write(JSON.stringify(probe.viewLossSubject===" + window + "));"
                )
                result = subprocess.run(["node", "-"], input=script, capture_output=True,
                                        text=True, timeout=10, check=False)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIs(json.loads(result.stdout), expected)

    def test_wake_reports_the_current_view_without_advancing_it(self):
        source = PROVIDER.read_text()
        start = source.index("onActivated: {", source.index("ShortcutHandler {"))
        body = block_function(source, start)[len("onActivated: "):]
        result = self.run_trace("probe.prepareTarget('Virtual-0');(function wake()" + body + ")();")
        self.assertEqual([(row["reason"], row["source"], row["from"], row["generation"],
                           row["prepared"]) for row in result["records"]],
                         [("wake", "wake", 0, 0, True)])
        self.assertEqual(result["generation"], 0)


# Synthetic but schema-exact native evidence for the complete sourced case.
EPOCH = "c" * 32
FOCUS, OTHER = "focus-boot", "other-boot"
OUT_A, OUT_B = "Virtual-0", "Virtual-1"
ACT_A, ACT_B = "activity-a", "activity-b"
DESK = "desktop-1"
LEASES = {FOCUS: EPOCH + ":1", OTHER: EPOCH + ":2"}
GEOMETRY = {OUT_A: (0, 0), OUT_B: (1440, 0)}
SHELL_PID = 700
STALE = {"ready": False, "reason": "stale-context", "token": ""}
# The provider issues a handle only with a preparation; a confirmed validation echoes none.
VALIDATED = {"intent": "validate", "ready": True, "reason": "", "token": ""}


def prepared_reply(token):
    return {"intent": "prepare", "ready": True, "reason": "", "token": token}


class ViewLossFixture:
    def __init__(self, root: Path, faults=()):
        self.root, self.faults = root, set(faults)
        self.shell, self.backend = [], []
        self.generation = self.revision = 0
        self.requests = {FOCUS: 0, OTHER: 0}
        self.retained = {}
        self.screens = [(OUT_A, True), (OUT_B, True)]
        self.activity, self.activities = ACT_A, 1
        self.subject_output = OUT_A
        self.hide_subject = False

    def emit(self, log, kind, row):
        log.append(f"qml: layout-probe-{kind} {json.dumps(row)}\n")

    def flush(self):
        (self.root / "plasmashell.log").write_text("".join(self.shell))
        (self.root / "kwin.log").write_text("".join(self.backend))

    def view(self, reason, source, prepared=False):
        before = self.generation
        if reason != "wake":
            self.generation += 1
        x, y = GEOMETRY[self.subject_output]
        self.emit(self.backend, "view", {
            "reason": reason, "source": source, "from": before, "generation": self.generation,
            "prepared": prepared,
            "screens": [{"name": name, "known": known, "x": GEOMETRY[name][0],
                         "y": GEOMETRY[name][1], "width": 1440, "height": 900}
                        for name, known in self.screens],
            "activityId": self.activity, "activities": self.activities, "desktopId": DESK,
            "activeClass": APP, "activeOutput": self.subject_output,
            "subjectClass": "" if "not-evacuated" in self.faults and reason == "wake"
            and self.subject_output == OUT_B else APP,
            "subjectOutput": self.subject_output,
            "subjectFrame": {"x": x + 505, "y": y + 292, "width": 430, "height": 310},
            "subjectInView": (self.activity == ACT_A or "hidden-app-in-view" in self.faults)
            and not self.hide_subject,
        })
        self.screens = [(name, True) for name, _ in self.screens]

    def focus(self, event, active, remembered, popup=False, output=OUT_A):
        self.emit(self.backend, "focus", {
            "event": event, "activeClass": active, "activeEligible": active == APP,
            "activePid": SHELL_PID if active == "plasmashell" else 900,
            "activeDock": False, "activeDesktop": active == "plasmashell" and not popup,
            "activeAppletPopup": popup, "activeNormal": active == APP,
            "contextGeneration": self.generation, "rememberedClass": remembered,
            "rememberedAlive": bool(remembered),
            "rememberedCenter": {"x": 720, "y": 447} if remembered else None,
            "desktopId": DESK, "activityId": self.activity, "activeOutput": OUT_A,
            "rememberedOutput": output if remembered else "",
        })

    def control(self, boot, screen):
        x = 86 if boot == FOCUS else 370
        self.emit(self.shell, "focus-control", {"boot": boot, "x": x, "y": 28, "screen": screen,
                                                "validateX": x + 140, "validateY": 28})

    def context(self, boot, output=OUT_A):
        return {"epoch": EPOCH, "generation": self.generation, "desktopId": DESK,
                "activityId": self.activity, "outputName": output, "consumerLease": LEASES[boot]}

    def send(self, boot, intent="query", token="", context=None, output=OUT_A, keyboard=False):
        self.requests[boot] += 1
        request = self.requests[boot]
        if keyboard:
            self.emit(self.shell, "keyboard-query", {
                "boot": boot, "key": 32, "activeFocus": True, "screen": output,
                "request": request, "intent": intent})
        self.emit(self.shell, "observation", {
            "boot": boot, "phase": "unknown", "epoch": "", "revision": -1, "accepted": 0,
            "packet": None, "request": request})
        self.emit(self.shell, "query", {"boot": boot, "request": request, "deadlineMs": 10000})
        self.retained[boot] = {
            "consumer": boot, "request": request, "version": 1, "intent": intent,
            "outputName": output, "token": token,
            "viewEpoch": context["epoch"] if context else "",
            "viewGeneration": context["generation"] if context else -1,
            "desktopId": context["desktopId"] if context else "",
            "activityId": context["activityId"] if context else "",
            "viewOutputName": context["outputName"] if context else "",
            "consumerLease": context["consumerLease"] if context else ""}
        return self.retained[boot]

    def reply(self, boot, preparation=None, context=None, accepted=True, received=True,
              alive=None):
        self.revision += 1
        request = self.retained[boot]["request"]
        packet = {"consumer": boot, "epoch": EPOCH, "revision": self.revision, "status": "online",
                  "capable": True, "refusal": -1, "request": request, "preparation": preparation,
                  "targetContext": context, "competingProviderRejected": True,
                  "backendOwner": ":1.0", "identityName": "org.plasmafusion.LayoutProbe.p" + EPOCH}
        if preparation:
            self.emit(self.backend, "target", {
                "consumer": boot, "request": request, "intent": preparation["intent"],
                "revision": self.revision, "ready": preparation["ready"],
                "reason": preparation["reason"],
                "targetClass": APP if (preparation["ready"] if alive is None else alive) else "",
                "targetAlive": preparation["ready"] if alive is None else alive})
        if received:
            self.emit(self.shell, "received", packet | {"receiverBoot": boot})
        if accepted:
            self.accept(packet)
        return packet

    def accept(self, packet):
        self.emit(self.shell, "observation", {
            "boot": packet["consumer"], "phase": "online", "epoch": EPOCH,
            "revision": packet["revision"], "accepted": 1, "packet": packet,
            "request": packet["request"]})

    def inventory(self, label):
        rows = [{"id": 24, "request": self.retained[FOCUS]},
                {"id": 25, "request": self.retained[OTHER]}]
        (self.root / f"view-{label}-inventory.json").write_text(json.dumps(rows))

    def mark(self, label):
        self.flush()
        view_loss.mark(self.root, label)

    def step(self, name):
        self.flush()
        return view_loss.record_step(self.root, name)

    def stale(self, intent="validate", context=None):
        return self.reply(FOCUS, {"intent": intent} | STALE, context)

    def activate_app(self, output=OUT_A):
        self.view("focus-changed", "activation")
        self.focus("activation", "plasmashell", "")
        self.view("focus-changed", "activation")
        self.focus("activation", APP, APP, output=output)

    def popup(self, remembered=APP):
        self.view("focus-changed", "activation")
        self.focus("activation", "plasmashell", remembered, popup=True)

    def build(self, *, until=None):
        write_cleanup_fixture(self.root)
        (self.root / "focus-shell-pid.txt").write_text(f"{SHELL_PID}\n")
        steps = []

        def done(name):
            steps.append(self.step(name))
            return until == name

        # Prelude: both consumers attach, then the first explicit preparation and validation.
        self.send(FOCUS)
        self.reply(FOCUS, context=self.context(FOCUS))
        self.control(FOCUS, OUT_A)
        self.send(OTHER)
        self.reply(OTHER, context=self.context(OTHER))
        self.control(OTHER, OUT_A)
        self.view("focus-changed", "activation")
        self.focus("activation", APP, APP)
        menu = self.context(FOCUS)
        self.popup()
        self.send(FOCUS, "prepare", context=menu, keyboard=True)
        first = EPOCH + ":1"
        self.reply(FOCUS, prepared_reply(first), self.context(FOCUS))
        prepared = self.context(FOCUS)
        self.send(FOCUS, "validate", token=first, context=prepared, keyboard=True)
        self.reply(FOCUS, VALIDATED, self.context(FOCUS))

        late = None
        if self.faults & {"accept-after-start", "accept-after-start-dead"}:
            # A re-confirmation logged just before the mark and accepted just after it.
            late = self.reply(FOCUS, VALIDATED, self.context(FOCUS), accepted=False,
                              alive="accept-after-start-dead" not in self.faults)
        overlapping = bool(self.faults & {"old-read-answers-after-wake", "queued-read-answers"})
        if overlapping:
            self.backend.append("qml: layout-probe: read started\n")
        self.mark("start")
        if late:
            self.accept(late)
        if "verdict-before-wake" in self.faults:
            # A read already under way at the mark answers before the wake's own read does.
            self.reply(FOCUS, VALIDATED, self.context(FOCUS))
        self.view("wake", "wake", prepared=True)
        if overlapping:
            # The pre-wake read produces a valid verdict after the wake but before its own
            # read finishes. The wake's queued read has started and is not yet complete.
            self.reply(FOCUS, VALIDATED, self.context(FOCUS))
            self.backend.append("qml: layout-probe: read finished\n")
        self.backend.append("qml: layout-probe: read started\n")
        pending = bool(self.faults & {"old-read-answers-after-wake", "wake-read-pending",
                                      "verdict-before-wake"})
        if not pending:
            self.reply(FOCUS, VALIDATED, self.context(FOCUS))
            if "read-has-not-finished" not in self.faults:
                self.backend.append("qml: layout-probe: read finished\n")
        self.inventory("baseline")
        if done("baseline"):
            return

        if "unexpected-early-readiness" in self.faults:
            self.revision += 1
            self.emit(self.backend, "target", {
                "consumer": FOCUS, "request": 2, "intent": "validate", "revision": self.revision,
                "ready": True, "reason": "", "targetClass": APP, "targetAlive": True})
        self.mark("disable")
        if pending:
            # The wake's read answers only after the disable mark, before the output goes.
            self.reply(FOCUS, VALIDATED, self.context(FOCUS))
            self.backend.append("qml: layout-probe: read finished\n")
        self.subject_output = OUT_B
        self.view("target-departed", "window-output", prepared=True)
        listed = OUT_A if "removed-output-listed" in self.faults else OUT_B
        self.screens = [(listed, True)]
        self.view("view-changed", "activation" if "no-screens-source" in self.faults else "screens")
        if "loss-ready" in self.faults:
            self.reply(FOCUS, VALIDATED)
        reason = "focus-changed" if "loss-wrong-reason" in self.faults else "stale-context"
        self.reply(FOCUS, {"intent": "validate", "ready": False, "reason": reason, "token": ""},
                   self.context(FOCUS) if "loss-context" in self.faults else None,
                   accepted="loss-not-accepted" not in self.faults,
                   received="loss-not-received" not in self.faults)
        if "loss-resend" in self.faults:
            self.send(FOCUS, "validate", token=first, context=prepared)
            self.requests[FOCUS] -= 1
            self.retained[FOCUS] = self.retained[FOCUS] | {"request": self.requests[FOCUS]}
        self.control(FOCUS, OUT_A if "bar-not-moved" in self.faults else OUT_B)
        self.send(OTHER, output=OUT_B)
        other_context = self.context(OTHER, OUT_B)
        if "lease-changed" in self.faults:
            other_context["consumerLease"] = EPOCH + ":9"
        self.reply(OTHER, context=other_context)
        self.control(OTHER, OUT_B)
        if done("lost"):
            return

        self.mark("evacuated")
        self.view("wake", "wake")
        if done("evacuated"):
            return

        self.mark("enable")
        self.screens = [(OUT_A, "reused-output" in self.faults), (OUT_B, True)]
        if "restore-before-screens" in self.faults:
            # The app may report the returned output first; screens then sees it as known.
            self.subject_output = OUT_A
            self.view("target-departed", "window-output")
        self.view("view-changed", "screens")
        self.subject_output = OUT_A
        old = {}
        if "returned-old-generation" in self.faults:
            old = {"generation": prepared["generation"]}
        self.stale(context=self.context(FOCUS) | old)
        self.send(OTHER)
        self.reply(OTHER, context=self.context(OTHER))
        self.control(OTHER, OUT_A)
        self.stale(context=self.context(FOCUS) | old)
        self.control(FOCUS, OUT_A)
        if done("returned"):
            return

        self.mark("revalidate")
        changed = prepared
        if "envelope-changed" in self.faults:
            changed = prepared | {"generation": self.generation}
        self.send(FOCUS, "validate", token=first, context=changed)
        if "revalidate-retry" in self.faults:
            self.emit(self.shell, "query", {"boot": FOCUS, "request": self.requests[FOCUS],
                                            "deadlineMs": 10000})
        self.stale(context=self.context(FOCUS))
        self.inventory("revalidated")
        if done("revalidated"):
            return

        self.mark("activity-add")
        self.activities = 2
        self.view("view-changed",
                  "activation" if "activity-not-added" in self.faults else "activities")
        self.stale(context=self.context(FOCUS))
        if done("activity-added"):
            return

        self.mark("subject-a")
        self.hide_subject = "subject-hidden" in self.faults
        self.view("wake", "wake")
        self.hide_subject = False
        if done("subject-a"):
            return

        self.mark("recover-a")
        self.activate_app(OUT_B if "app-not-reestablished" in self.faults else OUT_A)
        self.stale(context=self.context(FOCUS))
        menu = self.context(FOCUS)
        self.popup()
        self.send(FOCUS, "prepare", context=menu, keyboard=True)
        third = first if "reused-token" in self.faults else EPOCH + ":2"
        self.reply(FOCUS, prepared_reply(third), self.context(FOCUS))
        recovered = self.context(FOCUS)
        self.send(FOCUS, "validate", token=third, context=recovered, keyboard=True)
        echoed = {"token": third} if "validate-echoes-token" in self.faults else {}
        self.reply(FOCUS, VALIDATED | echoed, self.context(FOCUS))
        if "recovered-envelope" in self.faults:
            self.retained[FOCUS] = self.retained[FOCUS] | {"token": EPOCH + ":9"}
        self.inventory("recovered")
        if done("recovered"):
            return

        self.mark("switch-b")
        self.activity = ACT_B
        self.view("view-changed",
                  "activation" if "activity-source-missing" in self.faults else "current-activity",
                  prepared=True)
        home = {"activityId": ACT_A} if "refusal-in-home-context" in self.faults else {}
        self.stale(context=self.context(FOCUS) | home)
        self.view("focus-changed", "activation")
        if done("activity-left"):
            return
        if "ready-in-gap" in self.faults:
            # Between step windows: only the whole-run audit can see this re-confirmation.
            self.reply(FOCUS, VALIDATED, self.context(FOCUS))

        self.mark("switch-a")
        self.activity = ACT_A
        self.view("view-changed", "current-activity")
        away = {"activityId": ACT_B} if "return-context-away" in self.faults else {}
        self.stale(context=self.context(FOCUS) | away)
        if done("activity-returned"):
            return

        self.mark("revalidate-a")
        self.send(FOCUS, "validate", token=third, context=recovered)
        self.stale(context=self.context(FOCUS))
        self.inventory("revalidated-a")
        if done("revalidated-a"):
            return

        self.activate_app()
        self.stale(context=self.context(FOCUS))
        self.mark("switch-b2")
        self.activity = ACT_B
        self.view("view-changed", "current-activity")
        self.focus("context-changed", "plasmashell",
                   APP if "candidate-kept-on-switch" in self.faults else "")
        if "switch-not-followed" not in self.faults:
            self.stale(context=self.context(FOCUS))
            self.reply(OTHER, context=self.context(OTHER))
        if done("activity-left-again"):
            return

        self.mark("popup-b")
        menu = self.context(FOCUS)
        self.popup(remembered=APP if "popup-remembers-app" in self.faults else "")
        if done("popup-b"):
            return

        self.mark("wrong-view")
        self.send(FOCUS, "prepare", context=menu, keyboard=True)
        if "wrong-view-capture" in self.faults:
            self.reply(FOCUS, prepared_reply(EPOCH + ":3"), self.context(FOCUS))
        else:
            home = {"activityId": ACT_A} if "wrong-view-home-context" in self.faults else {}
            self.stale("prepare", self.context(FOCUS) | home)
        if done("wrong-view"):
            return

        self.mark("switch-a2")
        self.view("focus-changed", "activation")
        self.activity = ACT_A
        self.view("view-changed", "current-activity")
        if "return-not-followed" not in self.faults:
            self.reply(FOCUS, {"intent": "prepare", "ready": False, "reason": "refused",
                               "token": ""}, self.context(FOCUS))
            self.reply(OTHER, context=self.context(OTHER))
        if done("activity-returned-again"):
            return

        self.mark("subject-final")
        self.view("wake", "wake")
        if done("subject-final"):
            return

        self.mark("recover-final")
        self.activate_app()
        self.stale("prepare", self.context(FOCUS))
        menu = self.context(FOCUS)
        self.popup()
        self.send(FOCUS, "prepare", context=menu, keyboard=True)
        fourth = third if "final-reuses-token" in self.faults else EPOCH + ":4"
        self.reply(FOCUS, prepared_reply(fourth), self.context(FOCUS))
        if done("final"):
            return
        if self.faults & {"ready-in-gap", "accept-after-start-dead", "unexpected-early-readiness"}:
            # A forged receipt: the scope check must still recompute and refuse the run.
            (self.root / "view-loss-result.json").write_text(json.dumps({
                "schema": 1, "passed": True, "checks": view_loss.CHECKS}))
        else:
            view_loss.write_receipt(self.root)
        (self.root / "scenario.log").write_text("scenario rc=0\nsession rc=0\n")
        return steps


class ViewLossCheckerTests(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory(prefix="pf-view-check-")
        self.addCleanup(scratch.cleanup)
        self.root = Path(scratch.name)

    def build(self, *faults, until=None):
        return ViewLossFixture(self.root, faults).build(until=until)

    def check(self):
        return subprocess.run(
            [sys.executable, str(PREPARER), "--check-result", str(self.root),
             "--scope", "view-loss"],
            capture_output=True, text=True, timeout=20, check=False,
        )

    def append(self, log, kind, row):
        with (self.root / log).open("a") as output:
            output.write(f"qml: layout-probe-{kind} {json.dumps(row)}\n")

    def test_complete_view_loss_case_qualifies_from_raw_evidence_and_cleanup(self):
        self.build()
        result = self.check()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("view-loss", result.stdout)

    def test_baseline_cannot_use_a_pre_wake_read_that_answers_after_the_wake(self):
        with self.assertRaisesRegex(ValueError, "baseline wake"):
            self.build("old-read-answers-after-wake", until="baseline")

    def test_baseline_waits_until_the_post_wake_read_finishes(self):
        with self.assertRaisesRegex(ValueError, "baseline wake"):
            self.build("read-has-not-finished", until="baseline")

    def test_baseline_uses_the_queued_read_after_the_earlier_read_finishes(self):
        self.build("queued-read-answers")
        result = self.check()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_each_step_record_is_exclusive_and_bound_to_its_mark(self):
        self.build(until="baseline")
        with self.assertRaises(FileExistsError):
            view_loss.record_step(self.root, "baseline")
        with self.assertRaises(FileExistsError):
            view_loss.mark(self.root, "start")
        result = subprocess.run([sys.executable, str(VIEW), "step", str(self.root), "lost"],
                                capture_output=True, text=True, timeout=10, check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("view-mark-disable.json", result.stderr)

    def test_mark_ignores_a_partial_final_line(self):
        (self.root / "plasmashell.log").write_text('qml: x\nqml: layout-probe-observation {"boot":')
        (self.root / "kwin.log").write_text("qml: y\n")
        self.assertEqual(view_loss.mark(self.root, "start"),
                         {"schema": 1, "shellLines": 1, "kwinLines": 1})
        for label in ("../start", "Start", ""):
            with self.subTest(label=label), self.assertRaises(ValueError):
                view_loss.mark(self.root, label)

    def test_scenario_values_come_from_saved_records(self):
        self.build(until="subject-a")
        result = subprocess.run([sys.executable, str(VIEW), "value", str(self.root),
                                 "subject-a", "x"], capture_output=True, text=True, timeout=10,
                                check=False)
        self.assertEqual((result.returncode, result.stdout.strip()), (0, "720.0"), result.stderr)
        result = subprocess.run([sys.executable, str(VIEW), "value", str(self.root),
                                 "baseline", "envelope", "request"], capture_output=True, text=True,
                                timeout=10, check=False)
        self.assertEqual((result.returncode, result.stdout.strip()), (0, "3"), result.stderr)

    def test_step_faults_are_refused_where_the_native_wait_would_stop(self):
        for fault, message in (
            ("wake-read-pending", "baseline wake"),
            ("verdict-before-wake", "baseline wake"),
            ("no-screens-source", "screens event"),
            ("removed-output-listed", "screens event"),
            ("loss-ready", "became ready"),
            ("loss-wrong-reason", "refusal"),
            ("loss-not-accepted", "live receiver"),
            ("loss-not-received", "live receiver"),
            ("loss-resend", "automatic resend"),
            ("lease-changed", "unchanged lease"),
            ("not-evacuated", "evacuated"),
            ("reused-output", "new native output"),
            ("envelope-changed", "captured view or handle"),
            ("app-not-reestablished", "re-established"),
            ("reused-token", "invalidated handle"),
            ("validate-echoes-token", "explicit recovery"),
            ("loss-context", "removed output still produced a target context"),
            ("bar-not-moved", "survive on the remaining output"),
            ("returned-old-generation", "in a newer context"),
            ("activity-not-added", "activity creation lacks"),
            ("subject-hidden", "not visible on the returned output"),
            ("recovered-envelope", "does not match its handle"),
            ("refusal-in-home-context", "other activity's context"),
            ("candidate-kept-on-switch", "kept the other activity's application"),
            ("popup-remembers-app", "popup is not focused"),
            ("revalidate-retry", "not one explicit request"),
            ("return-context-away", "did not keep the old handle refused"),
            ("wrong-view-home-context", "lacked its own view context"),
            ("final-reuses-token", "invalidated handle"),
            ("switch-not-followed", "did not follow the activity switch"),
            ("return-not-followed", "did not follow the activity switch"),
            ("activity-source-missing", "activity switch"),
            ("hidden-app-in-view", "original activity"),
            ("wrong-view-capture", "became ready"),
        ):
            with self.subTest(fault=fault):
                for path in self.root.iterdir():
                    path.unlink()
                with self.assertRaisesRegex(ValueError, message):
                    self.build(fault)

    def test_same_name_return_does_not_depend_on_which_event_reports_it_first(self):
        self.build("restore-before-screens")
        rows = [json.loads(line.split("layout-probe-view ", 1)[1])
                for line in (self.root / "kwin.log").read_text().splitlines()
                if "layout-probe-view " in line]
        screens = [row for row in rows if row["source"] == "screens"][-1]
        self.assertEqual([(row["name"], row["known"]) for row in screens["screens"]],
                         [(OUT_A, True), (OUT_B, True)])
        result = self.check()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_tampered_saved_records_or_marks_cannot_qualify(self):
        self.build()
        path = self.root / "view-lost.json"
        record = json.loads(path.read_text())
        record["refusalRevision"] += 1
        path.write_text(json.dumps(record))
        result = self.check()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("raw evidence", result.stderr)

    def test_missing_step_evidence_cannot_qualify(self):
        self.build()
        (self.root / "view-mark-switch-a.json").unlink()
        result = self.check()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("view-mark-switch-a.json", result.stderr)

    def test_overlapping_step_windows_cannot_reattribute_evidence(self):
        self.build()
        lost = json.loads((self.root / "view-lost.json").read_text())
        path = self.root / "view-mark-evacuated.json"
        mark = json.loads(path.read_text())
        mark["kwinLines"] = lost["end"]["kwinLines"] - 1
        path.write_text(json.dumps(mark))
        result = self.check()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("overlap", result.stderr)

    def test_an_unreported_generation_advance_fails_the_whole_run(self):
        self.build()
        rows = [json.loads(line.split("layout-probe-view ", 1)[1])
                for line in (self.root / "kwin.log").read_text().splitlines()
                if "layout-probe-view " in line]
        last = rows[-1]
        self.append("kwin.log", "view", last | {"reason": "view-changed", "source": "screens",
                                                "from": last["generation"] + 2,
                                                "generation": last["generation"] + 3})
        result = self.check()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unreported context advance", result.stderr)

    def test_unattributed_or_skipping_advances_fail_the_whole_run(self):
        for change, message in (({"source": "timer"}, "unattributed"),
                                ({"generation": None}, "skipped a generation")):
            with self.subTest(change=change):
                for path in self.root.iterdir():
                    path.unlink()
                self.build()
                rows = [json.loads(line.split("layout-probe-view ", 1)[1])
                        for line in (self.root / "kwin.log").read_text().splitlines()
                        if "layout-probe-view " in line]
                last = rows[-1]
                row = last | {"reason": "view-changed", "source": "screens",
                              "from": last["generation"], "generation": last["generation"] + 1}
                row |= {key: (last["generation"] + 2 if value is None else value)
                        for key, value in change.items()}
                self.append("kwin.log", "view", row)
                result = self.check()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(message, result.stderr)

    def test_only_the_live_original_validation_may_be_ready_before_the_change(self):
        # Keep the baseline's read valid: this extra verdict must fail the whole-run audit,
        # even though it arrives after the baseline waited and before the output is disabled.
        self.build("unexpected-early-readiness")
        result = self.check()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("before the view changes", result.stderr)

    def test_recovered_handles_are_ready_only_within_their_own_span(self):
        self.build("ready-in-gap")
        result = self.check()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unexpected native readiness during the view-loss case", result.stderr)
        (self.root / "view-loss-result.json").unlink()
        with self.assertRaisesRegex(ValueError, "unexpected native readiness"):
            view_loss.write_receipt(self.root)
        self.assertFalse((self.root / "view-loss-result.json").exists())
        for path in self.root.iterdir():
            path.unlink()
        self.build()
        recovered = json.loads((self.root / "view-recovered.json").read_text())
        self.append("kwin.log", "target", {
            "consumer": FOCUS, "request": recovered["validateRequest"], "intent": "validate",
            "revision": 999, "ready": True, "reason": "", "targetClass": APP,
            "targetAlive": True})
        result = self.check()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unexpected native readiness during the view-loss case", result.stderr)

    def test_accepted_readiness_needs_a_bounded_native_verdict(self):
        self.build()
        final = json.loads((self.root / "view-final.json").read_text())
        packet = {"consumer": FOCUS, "epoch": EPOCH, "revision": 999, "status": "online",
                  "capable": True, "refusal": -1, "request": final["request"],
                  "preparation": prepared_reply(final["token"]), "targetContext": None,
                  "competingProviderRejected": True, "backendOwner": ":1.0",
                  "identityName": "org.plasmafusion.LayoutProbe.p" + EPOCH}
        self.append("plasmashell.log", "observation", {
            "boot": FOCUS, "phase": "online", "epoch": EPOCH, "revision": 999, "accepted": 9,
            "packet": packet, "request": final["request"]})
        result = self.check()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("accepted readiness lacks its bounded native verdict", result.stderr)

    def test_a_ready_verdict_must_name_the_live_application_even_in_its_span(self):
        self.build()
        final = json.loads((self.root / "view-final.json").read_text())
        self.append("kwin.log", "target", {
            "consumer": FOCUS, "request": final["request"], "intent": "prepare",
            "revision": 999, "ready": True, "reason": "", "targetClass": "",
            "targetAlive": False})
        result = self.check()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unexpected native readiness during the view-loss case", result.stderr)

    def test_accepted_readiness_must_match_the_whole_bounded_exchange(self):
        self.build()
        final = json.loads((self.root / "view-final.json").read_text())
        rows = [json.loads(line.split("layout-probe-target ", 1)[1])
                for line in (self.root / "kwin.log").read_text().splitlines()
                if "layout-probe-target " in line]
        verdict = [row for row in rows if row["request"] == final["request"]
                   and row["ready"]][-1]
        request = final["request"] + 1
        packet = {"consumer": FOCUS, "epoch": EPOCH, "revision": verdict["revision"],
                  "status": "online", "capable": True, "refusal": -1, "request": request,
                  "preparation": prepared_reply(final["token"]), "targetContext": None,
                  "competingProviderRejected": True, "backendOwner": ":1.0",
                  "identityName": "org.plasmafusion.LayoutProbe.p" + EPOCH}
        self.append("plasmashell.log", "observation", {
            "boot": FOCUS, "phase": "online", "epoch": EPOCH, "revision": verdict["revision"],
            "accepted": 9, "packet": packet, "request": request})
        result = self.check()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("accepted readiness lacks its bounded native verdict", result.stderr)

    def test_a_pre_start_reconfirmation_may_be_accepted_after_the_mark(self):
        self.build("accept-after-start")
        start = json.loads((self.root / "view-mark-start.json").read_text())
        lines = (self.root / "plasmashell.log").read_text().splitlines()
        accepted = [json.loads(line.split("layout-probe-observation ", 1)[1])
                    for line in lines[start["shellLines"]:]
                    if "layout-probe-observation " in line]
        self.assertEqual(accepted[0]["packet"]["preparation"], VALIDATED)
        result = self.check()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_a_pre_start_reconfirmation_without_a_live_target_binds_nothing(self):
        self.build("accept-after-start-dead")
        result = self.check()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("accepted readiness lacks its bounded native verdict", result.stderr)

    def test_the_chain_starts_at_zero_and_wakes_never_advance(self):
        for label, message in (("", "does not start at generation 0"),
                               ("subject-a", "wake report changed the context generation")):
            with self.subTest(label=label or "first"):
                for path in self.root.iterdir():
                    path.unlink()
                self.build()
                path = self.root / "kwin.log"
                lines = path.read_text().splitlines(keepends=True)
                start = 0
                if label:
                    mark = json.loads((self.root / f"view-mark-{label}.json").read_text())
                    start = mark["kwinLines"]
                index = next(number for number, line in enumerate(lines) if number >= start
                             and "layout-probe-view " in line)
                row = json.loads(lines[index].split("layout-probe-view ", 1)[1])
                if label:
                    row["generation"] = row["from"] + 1
                else:
                    row |= {"from": row["from"] + 1, "generation": row["from"] + 2}
                lines[index] = "qml: layout-probe-view " + json.dumps(row) + "\n"
                path.write_text("".join(lines))
                result = self.check()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(message, result.stderr)

    def test_only_a_complete_check_writes_the_single_source_receipt(self):
        self.build()
        self.assertEqual(json.loads((self.root / "view-loss-result.json").read_text()),
                         {"schema": 1, "passed": True, "checks": view_loss.CHECKS})
        again = subprocess.run([sys.executable, str(VIEW), "receipt", str(self.root)],
                               capture_output=True, text=True, timeout=20, check=False)
        self.assertNotEqual(again.returncode, 0)
        self.assertIn("File exists", again.stderr)
        (self.root / "view-loss-result.json").unlink()
        path = self.root / "view-wrong-view.json"
        path.write_text(json.dumps(json.loads(path.read_text()) | {"request": 0}))
        refused = subprocess.run([sys.executable, str(VIEW), "receipt", str(self.root)],
                                 capture_output=True, text=True, timeout=20, check=False)
        self.assertNotEqual(refused.returncode, 0)
        self.assertIn("raw evidence", refused.stderr)
        self.assertFalse((self.root / "view-loss-result.json").exists())

    def test_late_readiness_hidden_requests_or_read_only_intents_fail_the_whole_run(self):
        for log, kind, row, message in (
            ("kwin.log", "target", {"consumer": FOCUS, "request": 9, "intent": "validate",
                                    "revision": 999, "ready": True, "reason": "",
                                    "targetClass": APP, "targetAlive": True},
             "unexpected native readiness"),
            ("plasmashell.log", "query", {"boot": FOCUS, "request": 10, "deadlineMs": 10000},
             "guarded-consumer requests"),
            ("kwin.log", "target", {"consumer": OTHER, "request": 4, "intent": "prepare",
                                    "revision": 999, "ready": False, "reason": "busy",
                                    "targetClass": "", "targetAlive": False},
             "read-only consumer"),
        ):
            with self.subTest(message=message):
                for path in self.root.iterdir():
                    path.unlink()
                self.build()
                self.append(log, kind, row)
                result = self.check()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(message, result.stderr)

    def test_a_replaced_provider_or_lease_after_the_case_fails_the_whole_run(self):
        for change, message in (({"epoch": "d" * 32}, "provider lifetime"),
                                ({"lease": EPOCH + ":7"}, "consumer lease")):
            with self.subTest(message=message):
                for path in self.root.iterdir():
                    path.unlink()
                self.build()
                context = {"epoch": EPOCH, "generation": 99, "desktopId": DESK,
                           "activityId": ACT_A, "outputName": OUT_A,
                           "consumerLease": change.get("lease", LEASES[OTHER])}
                packet = {"consumer": OTHER, "epoch": change.get("epoch", EPOCH), "revision": 999,
                          "status": "online", "capable": True, "refusal": -1, "request": 3,
                          "preparation": None, "targetContext": context,
                          "competingProviderRejected": True, "backendOwner": ":1.0",
                          "identityName": "org.plasmafusion.LayoutProbe.p" + EPOCH}
                self.append("plasmashell.log", "observation", {
                    "boot": OTHER, "phase": "online", "epoch": packet["epoch"], "revision": 999,
                    "accepted": 9, "packet": packet, "request": 3})
                result = self.check()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(message, result.stderr)

    def test_scope_requires_its_own_receipt_and_the_cleanup_gate(self):
        for remove, message in (("view-loss-result.json", "view-loss-result.json"),
                                ("cleanup-result.json", "cleanup")):
            with self.subTest(remove=remove):
                for path in self.root.iterdir():
                    path.unlink()
                self.build()
                (self.root / remove).unlink()
                result = self.check()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(message, result.stderr)

    def test_other_receipts_cannot_stand_in_for_the_view_loss_scope(self):
        self.build()
        (self.root / "view-loss-result.json").unlink()
        for name, checks in (("mixed-lifetime-result.json", ["roundtrip-native"]),
                             ("target-preparation-result.json",
                              ["roundtrip-native", "guarded-target"])):
            receipt = {"schema": 1, "passed": True, "checks": checks}
            (self.root / name).write_text(json.dumps(receipt))
        result = self.check()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("view-loss-result.json", result.stderr)


if __name__ == "__main__":
    unittest.main()
