# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Native target/view guard cases; also loaded by test_prepare_seed.py."""

import contextlib
import importlib
import io
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

if __package__:
    from .qml_helpers import qml_handler
else:
    from qml_helpers import qml_handler


def run_bridge_wait(name: str, arguments: list[str], *, checks_pass: bool):
    """Run one of the bridge's target waits on its own, as the bridge defines it.

    The function's text is cut from scenario-bridge.sh and run in bash under the bridge's own
    errexit settings. python3 is stubbed to pass or fail every check, writing one "check" line to
    its stderr, which the wait sends to its own log; sleep only records its argument, and evaljs
    only reads the script it is given. Returns the bash result and the scratch files' texts.
    """
    bridge = Path(__file__).with_name("scenario-bridge.sh").read_text()
    head = f"    {name}() {{\n"
    assert bridge.count(head) == 1, name
    body = bridge.split(head, 1)[1].split("\n    }\n", 1)[0]
    script = ("set -euo pipefail\n"
              f"python3() {{ echo check >&2; return {0 if checks_pass else 1}; }}\n"
              'sleep() { echo "$1" >>"$OUT/sleeps"; }\n'
              "evaljs() { cat >/dev/null; }\n"
              f"{name}() {{\n{body}\n}}\n"
              f'{name} "$@"\n')
    with tempfile.TemporaryDirectory(prefix="pf-layout-wait-") as scratch:
        result = subprocess.run(["/usr/bin/bash", "-c", script, name, *arguments],
                                env={"PATH": "/usr/bin:/bin", "OUT": scratch, "HOME": scratch},
                                capture_output=True, text=True, timeout=30, check=False)
        files = {path.name: path.read_text() for path in Path(scratch).iterdir()
                 if path.is_file()}
    return result, files


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
            "consumer": "current", "request": 4, "revision": 5, "preparation": {
                "intent": "validate", "ready": False, "reason": "focus-changed", "token": "",
            },
        }}
        # The provider logs one verdict per published frame, numbered as that frame.
        native = {"consumer": "current", "request": 4, "intent": "validate", "revision": 5,
                  "ready": False, "targetAlive": False, "targetClass": ""}
        verdicts = [native]
        if fault == "old-state":
            observation["request"] = observation["packet"]["request"] = 3
        elif fault == "wrong-receiver":
            observation["packet"]["consumer"] = "other"
        elif fault == "wrong-native":
            native["ready"] = True
        elif fault == "newer-verdict":
            # A later publication re-validated the same request differently.
            verdicts.append(native | {"revision": 6, "ready": True, "targetAlive": True,
                                      "targetClass": "pf.focus.alpha"})
        elif fault == "missing-own-verdict":
            native["revision"] = 6
        events = [("query", outbound), ("observation", observation)]
        if fault == "out-of-order":
            events.reverse()
        elif fault == "received-not-accepted":
            events[-1] = ("received", observation)
        with tempfile.TemporaryDirectory(prefix="pf-target-check-") as scratch:
            root = Path(scratch)
            shell = root / "shell.log"
            shell.write_text("".join(
                f"qml: layout-probe-{kind} {json.dumps(row)}\n" for kind, row in events
            ))
            backend = root / "kwin.log"
            backend.write_text("".join("qml: layout-probe-target " + json.dumps(row) + "\n"
                                       for row in verdicts))
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

    def test_a_newer_verdict_for_the_same_request_cannot_replace_the_accepted_ones(self):
        result = self.run_target_checker("newer-verdict")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_the_accepted_revision_needs_its_own_native_verdict(self):
        self.assertNotEqual(self.run_target_checker("missing-own-verdict").returncode, 0)


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
        with tempfile.TemporaryDirectory(prefix="pf-settle-") as scratch:
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

    def test_a_change_between_its_reads_cannot_settle_on_the_older_generation(self):
        receipts = importlib.import_module(
            f"{__package__}.receipts" if __package__ else "receipts")
        observation = {"boot": "current", "phase": "online", "epoch": "e", "revision": 9,
                       "accepted": 3, "request": 4, "packet": {
                           "consumer": "current", "request": 4,
                           "targetContext": {"epoch": "e", "generation": 7}}}
        busy = receipts.provider_busy

        def change_meanwhile(path):
            # The provider observes a change, reads and publishes, all after the receiver read.
            with open(path, "a") as log:
                log.write("qml: layout-probe-focus "
                          + json.dumps({"event": "activation", "contextGeneration": 8}) + "\n"
                          + "qml: layout-probe: read started\n"
                          + "qml: layout-probe: publication online 2\n"
                          + "qml: layout-probe: read finished\n"
                          + "qml: layout-probe: publication writes 2\n")
            return busy(path)

        with tempfile.TemporaryDirectory(prefix="pf-settle-race-") as scratch:
            shell, kwin = Path(scratch) / "plasmashell.log", Path(scratch) / "kwin.log"
            shell.write_text("qml: layout-probe-observation " + json.dumps(observation) + "\n")
            kwin.write_text("qml: layout-probe-focus "
                            + json.dumps({"event": "removed", "contextGeneration": 7}) + "\n")
            with (mock.patch.object(receipts, "provider_busy", side_effect=change_meanwhile),
                  contextlib.redirect_stdout(io.StringIO())):
                with self.assertRaises(AssertionError):
                    receipts.target_settled(["receipts.py", str(shell), str(kwin), "current",
                                             "7"])

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
        never, _ = run_bridge_wait("wait_target_settled", ["current", "8"], checks_pass=False)
        self.assertEqual(never.returncode, 1, never.stderr)


class TargetWaitTimeoutTests(unittest.TestCase):
    """Each of the bridge's target waits names itself when it gives up.

    The bridge runs under errexit, so a wait that only returned non-zero stopped the scenario with
    nothing in its log after the last PASS line; the keyboard-entry scenario uses three of them.
    """

    # The wait, arguments as the bridge passes them, the label its FAIL line starts with, what it
    # must name from the arguments, and the log that holds the reason its last check failed.
    WAITS = (
        ("wait_target_reply", ["current", "validate", "false", "5", "-"], "target reply",
         ("validate reply", "ready false", "after request 5", "for no app"),
         "target-reply-wait.log"),
        ("wait_target_reply", ["current", "prepare", "true", "1", "pf.focus.alpha"],
         "target reply", ("prepare reply", "ready true", "after request 1", "for pf.focus.alpha"),
         "target-reply-wait.log"),
        ("wait_target_context", ["current", "pf.focus.alpha"], "target context",
         ("remembering pf.focus.alpha",), "target-context-wait.log"),
        ("wait_consumer_state", ["current", "4", "prepare", "false", "busy", "-"],
         "consumer state", ("after revision 4", "prepare ready false", "reason busy",
                            "for no app"), "consumer-state-wait.log"),
        ("wait_consumer_state", ["current", "6", "prepare", "true", "-", "pf.focus.alpha"],
         "consumer state", ("after revision 6", "prepare ready true", "reason none",
                            "for pf.focus.alpha"), "consumer-state-wait.log"),
        ("wait_target_settled", ["current", "8"], "target settle",
         ("at or after context generation 8",), "target-settle-wait.log"),
        ("wait_target_popup", ["pf.focus.beta"], "target popup",
         ("with pf.focus.beta remembered",), "target-popup-wait.log"),
        ("wait_second_app_active", [], "second app", ("pf.focus.beta",),
         "target-second-wait.log"),
        ("wait_owned_consumer_removed", [], "consumer removal",
         ("remaining owned probe widget",), "consumer-removal-wait.log"),
    )

    def test_each_target_wait_names_itself_and_its_log_when_it_times_out(self):
        for name, arguments, label, named, log in self.WAITS:
            with self.subTest(wait=name, arguments=arguments):
                result, files = run_bridge_wait(name, arguments, checks_pass=False)
                self.assertEqual(result.returncode, 1, result.stderr)
                lines = result.stderr.splitlines()
                self.assertEqual(len(lines), 1, result.stderr)
                self.assertTrue(lines[0].startswith(f"FAIL: {label}: "), lines[0])
                for fragment in (*named, f"(last check: {log})"):
                    self.assertIn(fragment, lines[0])
                self.assertEqual(result.stdout, "")
                # The log the line names is the one all 40 checks wrote to, 0.1 s apart.
                self.assertEqual(files.get(log, "").splitlines(), ["check"] * 40)
                self.assertEqual(files["sleeps"].splitlines(), ["0.1"] * 40)

    def test_each_target_wait_returns_quietly_once_its_check_passes(self):
        for name, arguments, _, _, log in self.WAITS:
            with self.subTest(wait=name, arguments=arguments):
                result, files = run_bridge_wait(name, arguments, checks_pass=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stderr, "")
                self.assertEqual(files.get(log, "").splitlines(), ["check"])
                self.assertNotIn("sleeps", files)


if __name__ == "__main__":
    unittest.main()
