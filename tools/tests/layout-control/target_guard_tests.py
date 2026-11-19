# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Native target/view guard cases; also loaded by test_prepare_seed.py."""

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

if __package__:
    from .qml_helpers import qml_handler
else:
    from qml_helpers import qml_handler


class TargetGuardTests(unittest.TestCase):
    def run_guard(self, action, *, requests=False):
        rules = (Path(__file__).resolve().parents[3] /
                 "packages/kwin/scripts/plasmafusion-placement/contents/ui/Tiling.js").read_text()
        script = r"""
const vm = require('node:vm');
const Tiling = {};
vm.runInNewContext(RULES.replace(/^\.pragma library$/m, ''), Tiling);
const output = {name:'Virtual-0'}, otherOutput = {name:'Virtual-1'};
const desktop = {id:'desktop-a'}, otherDesktop = {id:'desktop-b'};
let currentDesktop = desktop;
const Workspace = {
    screens:[output], desktops:[desktop, otherDesktop], activities:['activity-a','activity-b'],
    currentActivity:'activity-a', currentDesktopForScreen:()=>currentDesktop, activeWindow:null
};
const app = {
    deleted:false, normalWindow:true, transient:false, modal:false, moveable:true, resizeable:true,
    fullScreen:false, tile:null, minimized:false, maximizeMode:0, skipTaskbar:false, skipSwitcher:false,
    desktops:[desktop], activities:[], output:output, pid:101
};
const panel = {
    deleted:false, normalWindow:false, appletPopup:true, dock:false, desktopWindow:false,
    output:output, pid:202
};
const probe = {
    authorized:true, capable:true, identityReady:true, stopping:false, readOwner:':1.20',
    shellPid:202, shellPidOwner:':1.20', lastEligibleWindow:app, preparedTarget:null,
    preparationFailure:'not-prepared', epoch:'a'.repeat(32), targetExchange:null, targetSerial:0,
    targetGeneration:0,lastFocusedWindow:panel,targetHandoff:null,
    targetConsumers:[],consumerSerial:0,inventoryOwner:'',targetInventoryComplete:false
};
Workspace.activeWindow = panel;
const methods = (function(){with(probe){return {
""".replace("RULES", json.dumps(rules))
        methods = ("shellOwnsFocus", "invalidateTarget", "targetContextReady", "targetViewIsCurrent",
                   "prepareTarget", "validateTarget", "trackTargetActivation",
                   "targetViewChanged", "targetMembershipChanged", "advanceTargetContext",
                   "captureTargetContext", "targetEligibilityChanged", "canUseTargetHandoff")
        if requests:
            methods += ("handleTargetRequest", "reconcileTargetConsumers", "targetConsumerFor")
        script += ",".join(name + ":" + qml_handler(name, "provider.qml") for name in methods)
        script += "};}})();Object.assign(probe,methods);\n"
        if requests:
            script += """
probe.reconcileTargetConsumers({complete:true,widgets:[{id:7,consumer:'current'},
                                                     {id:8,consumer:'other'}]});
const consumerLease=probe.targetConsumerFor(7,'current').lease;
const otherLease=probe.targetConsumerFor(8,'other').lease;
"""
        script += action
        result = subprocess.run(["node", "-"], input=script, capture_output=True, text=True,
                                timeout=10, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_preparation_retains_the_exact_native_app_behind_its_shell_popup(self):
        result = self.run_guard("""
const prepared = probe.prepareTarget('Virtual-0');
process.stdout.write(JSON.stringify({
    prepared, valid:probe.validateTarget(), exact:probe.preparedTarget.window===app
}));
""")
        self.assertEqual(result, {"prepared": True, "valid": True, "exact": True})

    def test_another_application_invalidates_instead_of_retargeting(self):
        result = self.run_guard("""
probe.prepareTarget('Virtual-0');
const other = {...app,pid:303};
Workspace.activeWindow = other;
probe.trackTargetActivation(other);
Workspace.activeWindow = panel;
process.stdout.write(JSON.stringify({
    valid:probe.validateTarget(), cleared:probe.preparedTarget===null,
    candidate:probe.lastEligibleWindow===other
}));
""")
        self.assertEqual(result, {"valid": False, "cleared": True, "candidate": True})

    def test_replaced_output_with_the_same_name_cannot_revalidate_a_target(self):
        result = self.run_guard("""
probe.prepareTarget('Virtual-0');
Workspace.screens = [{name:'Virtual-0'}];
const valid = probe.validateTarget();
Workspace.screens = [output];
process.stdout.write(JSON.stringify({
    valid, afterReturn:probe.validateTarget(), cleared:probe.preparedTarget===null
}));
""")
        self.assertEqual(result, {"valid": False, "afterReturn": False, "cleared": True})

    def test_unrelated_ineligible_focus_cannot_preserve_an_old_candidate(self):
        result = self.run_guard("""
probe.prepareTarget('Virtual-0');
const unrelated = {...app, minimized:true, resourceClass:'org.kde.plasmashell'};
Workspace.activeWindow = unrelated;
probe.trackTargetActivation(unrelated);
Workspace.activeWindow = panel;
process.stdout.write(JSON.stringify({
    valid:probe.validateTarget(), candidateCleared:probe.lastEligibleWindow===null,
    newPreparation:probe.prepareTarget('Virtual-0')
}));
""")
        self.assertEqual(result, {"valid": False, "candidateCleared": True, "newPreparation": False})

    def test_a_different_shell_surface_or_dismissed_menu_invalidates_the_preparation(self):
        for focus in ("{...panel}", "app"):
            with self.subTest(focus=focus):
                result = self.run_guard("""
probe.prepareTarget('Virtual-0');
const changedFocus = """ + focus + """;
Workspace.activeWindow = changedFocus;
probe.trackTargetActivation(changedFocus);
Workspace.activeWindow = panel;
process.stdout.write(JSON.stringify({
    valid:probe.validateTarget(),cleared:probe.preparedTarget===null
}));
""")
                self.assertEqual(result, {"valid": False, "cleared": True})

    def test_eligibility_notifies_preserve_a_valid_target_but_lost_eligibility_cannot_revive(self):
        handler = qml_handler("onMinimizedChanged", "provider.qml")
        result = self.run_guard(handler + """
probe.prepareTarget('Virtual-0');
onMinimizedChanged();
const stillValid=probe.validateTarget();
app.minimized=true;
onMinimizedChanged();
app.minimized=false;
process.stdout.write(JSON.stringify({stillValid,afterReturn:probe.validateTarget()}));
""")
        self.assertEqual(result, {"stillValid": True, "afterReturn": False})

    def test_shell_exceptions_require_verified_owner_pid_and_native_surface_type(self):
        for setup in (
            "panel.pid=303;panel.resourceClass='org.kde.plasmashell';",
            "panel.normalWindow=true;panel.appletPopup=false;",
            "probe.shellPid=0;",
            "probe.shellPidOwner=':1.99';",
            "panel.output=otherOutput;",
            "probe.lastEligibleWindow=null;",
            "Workspace.screens=[output,{name:'Virtual-0'}];",
        ):
            with self.subTest(setup=setup):
                self.assertFalse(self.run_guard(
                    setup + "process.stdout.write(JSON.stringify(probe.prepareTarget('Virtual-0')));"
                ))

    def test_loss_and_departure_clear_the_preparation_irreversibly(self):
        for change, restore in (
            ("Workspace.desktops=[];", "Workspace.desktops=[desktop,otherDesktop];"),
            ("Workspace.activities=[];", "Workspace.activities=['activity-a','activity-b'];"),
            ("currentDesktop=otherDesktop;", "currentDesktop=desktop;"),
            ("Workspace.currentActivity='activity-b';", "Workspace.currentActivity='activity-a';"),
            ("app.deleted=true;", "app.deleted=false;"),
            ("app.deleted=undefined;", "app.deleted=false;"),
            ("app.output=otherOutput;", "app.output=output;"),
            ("app.desktops=[otherDesktop];", "app.desktops=[desktop];"),
            ("app.activities=['activity-b'];", "app.activities=[];"),
            ("app.minimized=true;", "app.minimized=false;"),
            ("app.fullScreen=true;", "app.fullScreen=false;"),
            ("probe.stopping=true;", "probe.stopping=false;"),
            ("probe.readOwner=':1.99';", "probe.readOwner=':1.20';"),
        ):
            with self.subTest(change=change):
                result = self.run_guard("probe.prepareTarget('Virtual-0');" + change +
                                        "const valid=probe.validateTarget();" + restore + """
process.stdout.write(JSON.stringify({valid, afterReturn:probe.validateTarget()}));
""")
                self.assertEqual(result, {"valid": False, "afterReturn": False})

    def test_view_and_membership_events_prevent_leave_and_return_resurrection(self):
        for event in ("targetViewChanged", "targetMembershipChanged"):
            with self.subTest(event=event):
                result = self.run_guard("probe.prepareTarget('Virtual-0');probe." + event + """();
process.stdout.write(JSON.stringify({
    valid:probe.validateTarget(), candidateCleared:probe.lastEligibleWindow===null
}));
""")
                self.assertEqual(result, {"valid": False, "candidateCleared": True})

    def test_repeated_prepare_never_renews_or_retargets_the_same_intent(self):
        result = self.run_guard("""
const request = {version:1,id:7,consumer:'current',request:2,intent:'prepare',
                 consumerLease,
                 outputName:'Virtual-0',token:'',viewEpoch:probe.epoch,viewGeneration:0,
                 desktopId:'desktop-a',activityId:'activity-a',viewOutputName:'Virtual-0'};
const first = probe.handleTargetRequest(request);
const other = {...app,pid:303};
Workspace.activeWindow=other;
probe.trackTargetActivation(other);
const repeated = probe.handleTargetRequest(request);
process.stdout.write(JSON.stringify({
    first:first.ready, repeated:repeated.ready, targetCleared:probe.preparedTarget===null
}));
""", requests=True)
        self.assertEqual(result, {"first": True, "repeated": False, "targetCleared": True})

    def test_guarded_validation_binds_the_handle_to_consumer_and_payload(self):
        result = self.run_guard("""
const prepare = {version:1,id:7,consumer:'current',request:2,intent:'prepare',
                 consumerLease,
                 outputName:'Virtual-0',token:'',viewEpoch:probe.epoch,viewGeneration:0,
                 desktopId:'desktop-a',activityId:'activity-a',viewOutputName:'Virtual-0'};
const first=probe.handleTargetRequest(prepare);
const conflicting=probe.handleTargetRequest({...prepare,outputName:'Virtual-1'});
const stranger=probe.handleTargetRequest({...prepare,id:8,consumer:'other',request:3,
                                         consumerLease:otherLease});
const validate={...prepare,request:3,intent:'validate',token:first.token};
const confirmed=probe.handleTargetRequest(validate);
const reused=probe.handleTargetRequest({...validate,token:'changed'});
process.stdout.write(JSON.stringify({
    first:first.ready, conflicting:conflicting.ready, stranger:stranger.ready,
    confirmed:confirmed.ready, reused:reused.ready, exact:probe.preparedTarget.window===app
}));
""", requests=True)
        self.assertEqual(result, {"first": True, "conflicting": False, "stranger": False,
                                  "confirmed": True, "reused": False, "exact": True})

    def test_delayed_preparation_cannot_capture_a_later_focus_or_view(self):
        for change in (
            """currentDesktop=otherDesktop;probe.targetViewChanged();
               Workspace.activeWindow={...app,desktops:[otherDesktop],pid:303};
               probe.trackTargetActivation(Workspace.activeWindow);""",
            """Workspace.activeWindow={...app,pid:303};
               probe.trackTargetActivation(Workspace.activeWindow);""",
            """currentDesktop=otherDesktop;probe.targetViewChanged();
               currentDesktop=desktop;probe.targetViewChanged();Workspace.activeWindow=app;""",
        ):
            with self.subTest(change=change):
                result = self.run_guard("""
const request={version:1,id:7,consumer:'current',request:2,intent:'prepare',
               consumerLease,
               outputName:'Virtual-0',token:'',viewEpoch:probe.epoch,viewGeneration:0,
               desktopId:'desktop-a',activityId:'activity-a',viewOutputName:'Virtual-0'};
""" + change + """
const reply=probe.handleTargetRequest(request);
process.stdout.write(JSON.stringify({ready:reply.ready,cleared:probe.preparedTarget===null}));
""", requests=True)
                self.assertEqual(result, {"ready": False, "cleared": True})

    def test_pre_capture_popup_changes_or_dismissal_cannot_substitute_focus(self):
        for sequence in (
            "Workspace.activeWindow={...panel};probe.trackTargetActivation(Workspace.activeWindow);",
            "Workspace.activeWindow=app;probe.trackTargetActivation(app);",
            """Workspace.activeWindow=app;probe.trackTargetActivation(app);
               Workspace.activeWindow=panel;probe.trackTargetActivation(panel);""",
            """Workspace.activeWindow={...panel};probe.trackTargetActivation(Workspace.activeWindow);
               Workspace.activeWindow=panel;probe.trackTargetActivation(panel);""",
        ):
            with self.subTest(sequence=sequence):
                result = self.run_guard("""
const request={version:1,id:7,consumer:'current',request:2,intent:'prepare',
               consumerLease,
               outputName:'Virtual-0',token:'',viewEpoch:probe.epoch,viewGeneration:0,
               desktopId:'desktop-a',activityId:'activity-a',viewOutputName:'Virtual-0'};
""" + sequence + """
const reply=probe.handleTargetRequest(request);
process.stdout.write(JSON.stringify({ready:reply.ready,cleared:probe.preparedTarget===null}));
""", requests=True)
                self.assertEqual(result, {"ready": False, "cleared": True})

    def test_only_the_single_initial_menu_opening_handoff_is_permitted(self):
        result = self.run_guard("""
Workspace.activeWindow=app;
probe.lastFocusedWindow=app;
const request={version:1,id:7,consumer:'current',request:2,intent:'prepare',
               consumerLease,
               outputName:'Virtual-0',token:'',viewEpoch:probe.epoch,viewGeneration:0,
               desktopId:'desktop-a',activityId:'activity-a',viewOutputName:'Virtual-0'};
Workspace.activeWindow=panel;
probe.trackTargetActivation(panel);
const reply=probe.handleTargetRequest(request);
process.stdout.write(JSON.stringify({
    ready:reply.ready,generation:probe.targetGeneration,
    exact:probe.preparedTarget && probe.preparedTarget.focusSurface===panel
}));
""", requests=True)
        self.assertEqual(result, {"ready": True, "generation": 1, "exact": True})

    def keyboard_entry(self, surfaces, *, generation="probe.targetGeneration", remembered="app"):
        """The panel gets keyboard focus, a key on its focused control opens the popup, and a key in
        the popup prepares. The request carries the context the consumer held when the popup's
        control was activated: by default the one after the panels' activations."""
        return self.run_guard("""
const dock={deleted:false,normalWindow:false,appletPopup:false,dock:true,desktopWindow:false,
            output:output,pid:202};
const surface={...dock,dock:false,desktopWindow:true};
probe.lastEligibleWindow=""" + remembered + """;
Workspace.activeWindow=app;
probe.lastFocusedWindow=app;
""" + "".join(f"Workspace.activeWindow={name};"
              "probe.trackTargetActivation(Workspace.activeWindow);\n" for name in surfaces) + """
const request={version:1,id:7,consumer:'current',request:2,intent:'prepare',
               consumerLease,
               outputName:'Virtual-0',token:'',viewEpoch:probe.epoch,viewGeneration:""" + generation
            + """,
               desktopId:'desktop-a',activityId:'activity-a',viewOutputName:'Virtual-0'};
Workspace.activeWindow=panel;
probe.trackTargetActivation(panel);
const reply=probe.handleTargetRequest(request);
const target=probe.preparedTarget;
process.stdout.write(JSON.stringify({
    ready:reply.ready,generation:probe.targetGeneration,
    app:!!target && target.window===app,focus:!!target && target.focusSurface===panel,
    shellTarget:!!target && [dock,surface,panel].includes(target.window)
}));
""", requests=True)

    def test_keyboard_entry_through_a_panel_or_the_desktop_prepares_the_remembered_app(self):
        # The dock or desktop branch of the initial menu-opening handoff: the shell surface that had
        # keyboard focus keeps the remembered app, and the popup it opens may bridge one generation.
        for surface in ("dock", "surface"):
            with self.subTest(surface=surface):
                self.assertEqual(self.keyboard_entry([surface]),
                                 {"ready": True, "generation": 2, "app": True, "focus": True,
                                  "shellTarget": False})

    def test_keyboard_entry_across_two_panels_still_bridges_one_generation(self):
        result = self.keyboard_entry(["dock", "{...dock}"])
        self.assertEqual(result, {"ready": True, "generation": 3, "app": True, "focus": True,
                                  "shellTarget": False})

    def test_keyboard_entry_with_a_request_from_before_the_panel_focus_is_refused(self):
        # A consumer that had not yet seen the panel's activation sends the earlier generation.
        result = self.keyboard_entry(["dock"], generation="0")
        self.assertEqual(result, {"ready": False, "generation": 2, "app": False, "focus": False,
                                  "shellTarget": False})

    def test_keyboard_entry_refuses_when_nothing_can_be_handed_off(self):
        # Nothing remembered, a dock the shell does not own, or a shell dock on another output than
        # the popup's: no handoff, so the request from before the popup's activation is stale.
        refused = {"ready": False, "generation": 2, "app": False, "focus": False,
                   "shellTarget": False}
        for case, surfaces, remembered in (("no remembered app", ["dock"], "null"),
                                           ("foreign dock", ["{...dock,pid:999}"], "app"),
                                           ("dock on another output",
                                            ["{...dock,output:otherOutput}"], "app")):
            with self.subTest(case=case):
                self.assertEqual(self.keyboard_entry(surfaces, remembered=remembered), refused)

    def test_prepare_rejects_stale_provider_or_captured_view_identifiers(self):
        for field, value in (("viewEpoch", "b" * 32), ("desktopId", "desktop-b"),
                             ("activityId", "activity-b"), ("viewOutputName", "Virtual-1")):
            with self.subTest(field=field):
                result = self.run_guard("""
const request={version:1,id:7,consumer:'current',request:2,intent:'prepare',
               consumerLease,
               outputName:'Virtual-0',token:'',viewEpoch:probe.epoch,viewGeneration:0,
               desktopId:'desktop-a',activityId:'activity-a',viewOutputName:'Virtual-0'};
""" + f"request[{json.dumps(field)}]={json.dumps(value)};" + """
const reply=probe.handleTargetRequest(request);
process.stdout.write(JSON.stringify({ready:reply.ready,cleared:probe.preparedTarget===null}));
""", requests=True)
                self.assertEqual(result, {"ready": False, "cleared": True})

    def test_detached_shell_surface_refuses_without_dereferencing_a_null_output(self):
        result = self.run_guard("""
Workspace.activeWindow={...panel,output:null};
probe.lastFocusedWindow=Workspace.activeWindow;
const request={version:1,id:7,consumer:'current',request:2,intent:'prepare',
               consumerLease,
               outputName:'Virtual-0',token:'',viewEpoch:probe.epoch,viewGeneration:0,
               desktopId:'desktop-a',activityId:'activity-a',viewOutputName:'Virtual-0'};
const reply=probe.handleTargetRequest(request);
process.stdout.write(JSON.stringify({ready:reply.ready,cleared:probe.preparedTarget===null}));
""", requests=True)
        self.assertEqual(result, {"ready": False, "cleared": True})

    def test_refused_preparation_identity_cannot_be_reused_to_capture_later(self):
        result = self.run_guard("""
const request={version:1,id:7,consumer:'current',request:2,intent:'prepare',
               consumerLease,
               outputName:'Virtual-0',token:'',viewEpoch:probe.epoch,viewGeneration:2,
               desktopId:'desktop-a',activityId:'activity-a',viewOutputName:'Virtual-0'};
const refused=probe.handleTargetRequest(request);
Workspace.activeWindow={...app,pid:303};
probe.trackTargetActivation(Workspace.activeWindow);
Workspace.activeWindow=panel;
probe.trackTargetActivation(panel);
const later=probe.handleTargetRequest(request);
const changed=probe.handleTargetRequest({...request,desktopId:'changed'});
process.stdout.write(JSON.stringify({
    refused:refused.ready,later:later.ready,changed:changed.ready,cleared:probe.preparedTarget===null
}));
""", requests=True)
        self.assertEqual(result, {"refused": False, "later": False, "changed": False, "cleared": True})

    def run_target_checker(self, fault=None):
        outbound = {"boot": "current", "request": 4}
        observation = {"boot": "current", "request": 4, "phase": "online", "packet": {
            "consumer": "current", "request": 4, "preparation": {
                "intent": "validate", "ready": False, "reason": "focus-changed", "token": "",
            },
        }}
        native = {"consumer": "current", "request": 4, "intent": "validate",
                  "ready": False, "targetAlive": False, "targetClass": ""}
        if fault == "old-state":
            observation["request"] = observation["packet"]["request"] = 3
        elif fault == "wrong-receiver":
            observation["packet"]["consumer"] = "other"
        elif fault == "wrong-native":
            native["ready"] = True
        events = [("query", outbound), ("observation", observation)]
        if fault == "out-of-order":
            events.reverse()
        elif fault == "received-not-accepted":
            events[-1] = ("received", observation)
        with tempfile.TemporaryDirectory(prefix="pf-target-check-", dir="/tmp/opencode") as scratch:
            root = Path(scratch)
            shell = root / "shell.log"
            shell.write_text("".join(
                f"qml: layout-probe-{kind} {json.dumps(row)}\n" for kind, row in events
            ))
            backend = root / "kwin.log"
            backend.write_text("qml: layout-probe-target " + json.dumps(native) + "\n")
            return subprocess.run(
                [sys.executable, str(Path(__file__).with_name("receipts.py")), "target-reply",
                 str(shell), str(backend), "current", "validate", "false", "3", "-", str(root)],
                capture_output=True,
                text=True, timeout=10, check=False,
            )

    def test_target_receipt_accepts_only_a_correlated_accepted_native_refusal(self):
        result = self.run_target_checker()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_target_receipt_rejects_old_wrong_receiver_or_unaccepted_evidence(self):
        for fault in ("old-state", "wrong-receiver", "wrong-native",
                      "out-of-order", "received-not-accepted"):
            with self.subTest(fault=fault):
                self.assertNotEqual(self.run_target_checker(fault).returncode, 0)


class TargetSettleTests(unittest.TestCase):
    """The target scenario clicks after a context change only once the shell has applied it."""

    def settle(self, *, provider=7, receiver=7, minimum=7, phase="online", context=True,
               tail=(), mode="target-settled"):
        target = {"epoch": "e", "generation": receiver} if context else None
        packet = {"consumer": "current", "request": 4, "targetContext": target}
        observation = {"boot": "current", "phase": phase, "epoch": "e", "revision": 9,
                       "accepted": 3, "packet": packet if phase == "online" else None,
                       "request": 4}
        pipeline = ["qml: layout-probe: read started", "qml: layout-probe: publication online 2",
                    "qml: layout-probe: read finished", "qml: layout-probe: publication writes 2"]
        backend = [
            "qml: layout-probe-focus " + json.dumps({"event": "activation",
                                                    "contextGeneration": provider - 1}),
            *pipeline,
            "qml: layout-probe-focus " + json.dumps({"event": "removed",
                                                    "contextGeneration": provider}),
            *pipeline, *tail,
        ]
        with tempfile.TemporaryDirectory(prefix="pf-settle-", dir="/tmp/opencode") as scratch:
            shell = Path(scratch) / "plasmashell.log"
            shell.write_text("qml: layout-probe-observation " + json.dumps(observation) + "\n")
            kwin = Path(scratch) / "kwin.log"
            kwin.write_text("\n".join(backend) + "\n")
            arguments = ([str(shell), str(kwin), "current", str(minimum)]
                         if mode == "target-settled" else [str(kwin)])
            return subprocess.run(
                [sys.executable, str(Path(__file__).with_name("receipts.py")), mode, *arguments],
                capture_output=True, text=True, timeout=10, check=False)

    def test_a_receiver_with_the_newest_context_and_nothing_outstanding_is_settled(self):
        result = self.settle()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "7")

    def test_settling_needs_the_provider_to_have_observed_the_change(self):
        # Before the provider sees the change, its newest context is the old one, which the
        # receiver already holds.
        self.assertNotEqual(self.settle(minimum=8).returncode, 0)

    def test_settling_needs_the_receiver_to_hold_the_newest_context(self):
        for change in ({"receiver": 6}, {"phase": "unknown"}, {"context": False}):
            with self.subTest(change=change):
                self.assertNotEqual(self.settle(**change).returncode, 0)

    def test_settling_waits_for_an_outstanding_read_or_publication(self):
        cases = {
            "read": (["qml: layout-probe: read started"], False),
            "publication": (["qml: layout-probe: publication online 2"], False),
            "offline publication": (["qml: layout-probe: publication offline 2"], False),
            "failed publication": (["qml: layout-probe: publication online 2",
                                    "qml: layout-probe: publication failed"], True),
        }
        for case, (tail, settled) in cases.items():
            with self.subTest(case=case):
                self.assertEqual(self.settle(tail=tail).returncode == 0, settled)

    def test_the_provider_generation_is_its_newest_focus_observation(self):
        result = self.settle(mode="provider-generation")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "7")

    def test_each_click_after_a_context_change_waits_for_the_shell(self):
        # Each step's change, and how many context generations it advances at least: the second
        # app's activation, its close, and the switch to desktop 2 and back.
        bridge = Path(__file__).with_name("scenario-bridge.sh").read_text()
        start = bridge.index('echo "PASS: explicit preparation and keyboard validation retain')
        end = bridge.index('echo "PASS: leaving and returning to the desktop cannot revive')
        lines = [line.strip() for line in bridge[start:end].splitlines() if line.strip()]
        clicks = [index for index, line in enumerate(lines)
                  if line == 'pfinput "click $validate_x $validate_y"']
        self.assertEqual(len(clicks), 3)
        changes = (('heldclient.py" pf.focus.beta', 1),
                   ("printf 'quit\\n' >&\"$target_second_input\"", 1),
                   ("setCurrentDesktop 2", 2))
        previous = -1
        for click, (change, steps) in zip(clicks, changes):
            with self.subTest(change=change):
                self.assertEqual(lines[click - 1],
                                 f'wait_target_settled "$focus_boot" $((generation + {steps}))')
                trigger = max(index for index in range(previous + 1, click)
                              if change in lines[index])
                captures = [index for index in range(previous + 1, trigger)
                            if lines[index].startswith("generation=$(")
                            and "provider-generation" in lines[index]]
                self.assertTrue(captures, "no generation captured before the change")
            previous = click

    def test_the_settle_wait_runs_the_receipt_and_fails_when_the_shell_never_settles(self):
        bridge = Path(__file__).with_name("scenario-bridge.sh").read_text()
        body = bridge.split("    wait_target_settled() {\n", 1)[1].split("\n    }\n", 1)[0]
        self.assertIn('receipts.py" target-settled', body)
        self.assertIn('"$OUT/plasmashell.log" "$OUT/kwin.log" "$boot" "$minimum"', body)
        self.assertTrue(body.rstrip().endswith("[[ $settled == true ]]"))


if __name__ == "__main__":
    unittest.main()
