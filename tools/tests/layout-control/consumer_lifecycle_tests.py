# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Bounded live-consumer inventory and retirement cases for the private probe."""

import json
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

if __package__:
    from .qml_helpers import qml_handler
else:
    from qml_helpers import qml_handler


class ConsumerLifecycleTests(unittest.TestCase):
    def run_mailbox_snapshot(self, values):
        script = """
const vm=require('node:vm');
const probe={targetProbe:true};
const reader={arguments:[],call:()=>{}};
""" + qml_handler("readMailboxes", "provider.qml") + """
readMailboxes();
const values=VALUES;
let snapshot;
vm.runInNewContext(reader.arguments[0],{
    panels:()=>[{widgets:()=>values.map((text,index)=>({
        id:index+1,currentConfigGroup:[],readConfig:()=>text
    }))}],
    print:text=>{snapshot=JSON.parse(text);}
});
process.stdout.write(JSON.stringify(snapshot));
""".replace("VALUES", json.dumps(values))
        result = subprocess.run(["node", "-"], input=script, capture_output=True, text=True,
                                timeout=10, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def run_inventory(self, action, *, requests=False):
        script = """
const probe={
    epoch:'a'.repeat(32),readOwner:':1.20',inventoryOwner:'',targetInventoryComplete:false,
    targetConsumers:[],consumerSerial:0,targetExchange:null,preparedTarget:null,
    preparationFailure:'not-prepared',
    invalidateTarget:reason=>{probe.preparedTarget=null;probe.preparationFailure=reason;}
};
const snapshot={complete:true,widgets:[{id:7,consumer:'a'},{id:8,consumer:'b'}]};
const methods=(function(){with(probe){return {
"""
        methods = ("reconcileTargetConsumers", "targetConsumerFor", "consumeTargetInventory",
                   "captureTargetConsumerContext")
        if requests:
            methods += ("handleTargetRequest", "publish")
        script += ",".join(name + ":" + qml_handler(name, "provider.qml") for name in methods)
        script += "};}})();Object.assign(probe,methods);\n"
        if requests:
            script += """
let captures=0;
const output={name:'Virtual-0'};
const popup={deleted:false,pid:202,appletPopup:true,output};
const Workspace={activeWindow:popup};
const Tiling={alive:window=>!!window&&window.deleted===false};
probe.targetGeneration=0;probe.targetSerial=0;
probe.targetContextReady=()=>true;
probe.captureTargetContext=()=>({
    epoch:probe.epoch,generation:0,desktopId:'desktop',activityId:'activity',outputName:'Virtual-0'
});
probe.canUseTargetHandoff=()=>false;
probe.shellOwnsFocus=()=>true;
probe.prepareTarget=()=>{++captures;probe.preparedTarget={window:'captured'};return true;};
probe.validateTarget=()=>probe.preparedTarget!==null;
const request=(id,consumer,lease,number)=>({
    version:1,id,consumer,consumerLease:lease,request:number,intent:'prepare',token:'',
    outputName:'Virtual-0',viewEpoch:probe.epoch,viewGeneration:0,
    desktopId:'desktop',activityId:'activity',viewOutputName:'Virtual-0'
});
"""
        script += action
        result = subprocess.run(["node", "-"], input=script, capture_output=True, text=True,
                                timeout=10, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_complete_inventory_issues_stable_distinct_current_consumer_leases(self):
        result = self.run_inventory("""
const first=probe.reconcileTargetConsumers(snapshot);
const a=probe.targetConsumerFor(7,'a'),b=probe.targetConsumerFor(8,'b');
const lease=a.lease;
const repeated=probe.reconcileTargetConsumers(snapshot);
process.stdout.write(JSON.stringify({
    first,repeated,distinct:a.lease!==b.lease,stable:probe.targetConsumerFor(7,'a').lease===lease,
    count:probe.targetConsumers.length
}));
""")
        self.assertEqual(result, {"first": True, "repeated": True, "distinct": True,
                                  "stable": True, "count": 2})

    def test_confirmed_holder_loss_retires_slot_and_preserves_competitors_refusal_history(self):
        result = self.run_inventory("""
probe.reconcileTargetConsumers(snapshot);
const a=probe.targetConsumerFor(7,'a'),b=probe.targetConsumerFor(8,'b');
b.request=9;b.payload='busy-payload';b.outcome='busy';
probe.targetExchange={owner:probe.readOwner,id:7,consumer:'a',lease:a.lease};
probe.preparedTarget={window:'captured'};
probe.reconcileTargetConsumers({complete:true,widgets:[{id:8,consumer:'b'}]});
const current=probe.targetConsumerFor(8,'b');
process.stdout.write(JSON.stringify({
    slot:probe.targetExchange,guard:probe.preparedTarget,old:probe.targetConsumerFor(7,'a'),
    request:current.request,payload:current.payload,outcome:current.outcome
}));
""")
        self.assertEqual(result, {"slot": None, "guard": None, "old": None,
                                  "request": 9, "payload": "busy-payload", "outcome": "busy"})

    def test_incomplete_inventory_never_proves_absence(self):
        result = self.run_inventory("""
probe.reconcileTargetConsumers(snapshot);
const a=probe.targetConsumerFor(7,'a'),lease=a.lease;
probe.targetExchange={owner:probe.readOwner,id:7,consumer:'a',lease};
probe.preparedTarget={window:'captured'};
const incomplete=probe.reconcileTargetConsumers({complete:false,widgets:[{id:8,consumer:'b'}]});
const held=probe.targetExchange!==null,unconfirmed=probe.targetConsumerFor(7,'a')===null;
probe.reconcileTargetConsumers(snapshot);
process.stdout.write(JSON.stringify({
    incomplete,held,unconfirmed,stable:probe.targetConsumerFor(7,'a').lease===lease
}));
""")
        self.assertEqual(result, {"incomplete": False, "held": True,
                                  "unconfirmed": True, "stable": True})

    def test_malformed_inventory_fails_closed_without_retiring_a_known_holder(self):
        for invalid in (
            None, {}, {"complete": "true", "widgets": []},
            {"complete": True, "widgets": [{"id": 7, "consumer": "a"},
                                         {"id": 7, "consumer": "b"}]},
            {"complete": True, "widgets": [{"id": 0, "consumer": "a"}]},
            {"complete": True, "widgets": [{"id": i, "consumer": "a"} for i in range(1, 18)]},
        ):
            with self.subTest(invalid=invalid):
                result = self.run_inventory("""
probe.reconcileTargetConsumers(snapshot);
const a=probe.targetConsumerFor(7,'a');
probe.targetExchange={owner:probe.readOwner,id:7,consumer:'a',lease:a.lease};
const accepted=probe.reconcileTargetConsumers(""" + json.dumps(invalid) + """);
process.stdout.write(JSON.stringify({
    accepted,held:probe.targetExchange!==null,unconfirmed:probe.targetConsumerFor(7,'a')===null
}));
""")
                self.assertEqual(result, {"accepted": False, "held": True, "unconfirmed": True})

    def test_unreadable_request_does_not_mean_the_widget_disappeared(self):
        result = self.run_inventory("""
probe.reconcileTargetConsumers(snapshot);
const a=probe.targetConsumerFor(7,'a'),lease=a.lease;
probe.targetExchange={owner:probe.readOwner,id:7,consumer:'a',lease};
probe.reconcileTargetConsumers({complete:true,widgets:[{id:7,consumer:null},{id:8,consumer:'b'}]});
const held=probe.targetExchange!==null,unconfirmed=probe.targetConsumerFor(7,'a')===null;
probe.reconcileTargetConsumers(snapshot);
process.stdout.write(JSON.stringify({
    held,unconfirmed,stable:probe.targetConsumerFor(7,'a').lease===lease
}));
""")
        self.assertEqual(result, {"held": True, "unconfirmed": True, "stable": True})

    def test_replaced_and_reappearing_boots_never_reuse_an_old_lease(self):
        result = self.run_inventory("""
probe.reconcileTargetConsumers(snapshot);
const first=probe.targetConsumerFor(7,'a').lease;
probe.targetExchange={owner:probe.readOwner,id:7,consumer:'a',lease:first};
probe.preparedTarget={window:'captured'};
probe.reconcileTargetConsumers({complete:true,widgets:[{id:7,consumer:'new'}]});
const replaced=probe.targetConsumerFor(7,'new').lease;
const cleared=probe.targetExchange===null && probe.preparedTarget===null;
probe.reconcileTargetConsumers({complete:true,widgets:[{id:7,consumer:'a'}]});
process.stdout.write(JSON.stringify({
    cleared,fresh:first!==replaced && first!==probe.targetConsumerFor(7,'a').lease
}));
""")
        self.assertEqual(result, {"cleared": True, "fresh": True})

    def test_shell_owner_change_clears_old_slot_without_resetting_the_lease_serial(self):
        result = self.run_inventory("""
probe.reconcileTargetConsumers(snapshot);
const first=probe.targetConsumerFor(7,'a').lease;
probe.targetExchange={owner:probe.readOwner,id:7,consumer:'a',lease:first};
probe.preparedTarget={window:'captured'};
probe.readOwner=':1.30';
probe.reconcileTargetConsumers(snapshot);
process.stdout.write(JSON.stringify({
    cleared:probe.targetExchange===null && probe.preparedTarget===null,
    fresh:first!==probe.targetConsumerFor(7,'a').lease
}));
""")
        self.assertEqual(result, {"cleared": True, "fresh": True})

    def test_lease_capacity_cannot_wrap_or_partially_confirm_inventory(self):
        result = self.run_inventory("""
probe.consumerSerial=2147483646;
const accepted=probe.reconcileTargetConsumers(snapshot);
process.stdout.write(JSON.stringify({
    accepted,serial:probe.consumerSerial,confirmed:probe.targetInventoryComplete,
    count:probe.targetConsumers.length
}));
""")
        self.assertEqual(result, {"accepted": False, "serial": 2147483646,
                                  "confirmed": False, "count": 0})

    def test_a_busy_refusal_never_becomes_an_automatic_capture_after_retirement(self):
        result = self.run_inventory("""
probe.reconcileTargetConsumers(snapshot);
const a=probe.targetConsumerFor(7,'a'),b=probe.targetConsumerFor(8,'b');
const first=probe.handleTargetRequest(request(7,'a',a.lease,2));
const competing=request(8,'b',b.lease,2);
const busy=probe.handleTargetRequest(competing);
probe.reconcileTargetConsumers({complete:true,widgets:[{id:8,consumer:'b'}]});
const repeated=probe.handleTargetRequest(competing);
const beforeNew=captures;
const explicit=probe.handleTargetRequest({...competing,request:3});
process.stdout.write(JSON.stringify({
    first:first.ready,busy:busy.ready,repeated:repeated.ready,beforeNew,
    explicit:explicit.ready,captures
}));
""", requests=True)
        self.assertEqual(result, {"first": True, "busy": False, "repeated": False,
                                  "beforeNew": 1, "explicit": True, "captures": 2})

    def test_a_reappearing_actor_cannot_use_a_retired_request_lease(self):
        result = self.run_inventory("""
probe.reconcileTargetConsumers(snapshot);
const original=request(7,'a',probe.targetConsumerFor(7,'a').lease,2);
probe.handleTargetRequest(original);
probe.reconcileTargetConsumers({complete:true,widgets:[{id:8,consumer:'b'}]});
probe.reconcileTargetConsumers(snapshot);
const replay=probe.handleTargetRequest(original);
process.stdout.write(JSON.stringify({
    replay:replay.ready,captures,cleared:probe.preparedTarget===null
}));
""", requests=True)
        self.assertEqual(result, {"replay": False, "captures": 1, "cleared": True})

    def test_native_inventory_keeps_widgets_with_unreadable_or_oversized_requests(self):
        valid = json.dumps({"consumer": "current", "request": 1, "intent": "query"})
        snapshot = self.run_mailbox_snapshot([valid, "not-json", "x" * 2049])
        self.assertIs(snapshot["complete"], True)
        self.assertEqual(snapshot["widgets"], [
            {"id": 1, "consumer": "current"}, {"id": 2, "consumer": None},
            {"id": 3, "consumer": None},
        ])
        self.assertEqual(len(snapshot["rows"]), 1)

    def test_truncation_counts_widget_inventory_not_only_parseable_requests(self):
        snapshot = self.run_mailbox_snapshot(["not-json"] * 16 + [
            json.dumps({"consumer": "last", "request": 1, "intent": "query"}),
        ])
        self.assertIs(snapshot["complete"], False)
        self.assertEqual(len(snapshot["widgets"]), 16)
        self.assertEqual(snapshot["rows"], [])

    def test_contradictory_or_malformed_rows_cannot_make_a_complete_inventory_retire_a_holder(self):
        for rows in (None, [{"id": 7, "consumer": "a"}],
                     [{"id": 8, "consumer": "b"}, {"id": 8, "consumer": "b"}], []):
            with self.subTest(rows=rows):
                result = self.run_inventory("""
probe.reconcileTargetConsumers(snapshot);
const a=probe.targetConsumerFor(7,'a');
probe.targetExchange={owner:probe.readOwner,id:7,consumer:'a',lease:a.lease};
const accepted=probe.consumeTargetInventory({
    complete:true,widgets:[{id:8,consumer:'b'}],rows:ROWS
});
process.stdout.write(JSON.stringify({accepted,held:probe.targetExchange!==null,
                                   confirmed:probe.targetInventoryComplete}));
""".replace("ROWS", json.dumps(rows)))
                self.assertEqual(result, {"accepted": None, "held": True, "confirmed": False})

    def run_reader(self, value, *, failed=False):
        source = Path(__file__).with_name("provider.qml").read_text().split("id: reader\n", 1)[1]
        name = "onFailed: " if failed else "onFinished: value => "
        handler = re.search(re.escape(name) + r"(\{.*?\n        \})", source, re.S)[1]
        return self.run_inventory("""
probe.reconcileTargetConsumers(snapshot);
const actor=probe.targetConsumerFor(7,'a');
probe.targetExchange={owner:probe.readOwner,id:7,consumer:'a',lease:actor.lease};
probe.targetProbe=true;
let finished=0,published=0;
probe.finishRead=()=>++finished;
probe.queuePublication=()=>++published;
console.info=()=>{};console.warn=()=>{};
const callback=value=>""" + handler + """;
callback([VALUE]);
process.stdout.write(JSON.stringify({
    finished,published,held:probe.targetExchange!==null,
    confirmed:probe.targetInventoryComplete,current:probe.targetConsumerFor(7,'a')!==null
}));
""".replace("VALUE", json.dumps(value)))

    def test_reader_failure_or_malformed_snapshot_unconfirms_without_proving_widget_absence(self):
        for value in (
            "not-json", "[]", "null",
            json.dumps({"complete": False, "widgets": [], "rows": []}),
            json.dumps({"complete": True, "widgets": [{"id": 8, "consumer": "b"}], "rows": []}),
            json.dumps({"complete": True, "widgets": [{"id": 0, "consumer": None}], "rows": []}),
        ):
            with self.subTest(value=value):
                self.assertEqual(self.run_reader(value), {
                    "finished": 1, "published": 0, "held": True,
                    "confirmed": False, "current": False,
                })
        self.assertEqual(self.run_reader(None, failed=True), {
            "finished": 1, "published": 0, "held": True, "confirmed": False, "current": False,
        })

    def test_complete_native_reader_absence_retires_the_holder_even_without_requests(self):
        self.assertEqual(self.run_reader(json.dumps({"complete": True, "widgets": [], "rows": []})), {
            "finished": 1, "published": 1, "held": False, "confirmed": True, "current": False,
        })

    def test_published_context_has_only_the_current_consumers_freshness_lease(self):
        result = self.run_inventory("""
probe.reconcileTargetConsumers(snapshot);
const first=probe.captureTargetConsumerContext({id:7,consumer:'a',outputName:'Virtual-0'});
const second=probe.captureTargetConsumerContext({id:8,consumer:'b',outputName:'Virtual-0'});
const missing=probe.captureTargetConsumerContext({id:7,consumer:'retired',outputName:'Virtual-0'});
probe.reconcileTargetConsumers(null);
const unknown=probe.captureTargetConsumerContext({id:7,consumer:'a',outputName:'Virtual-0'});
process.stdout.write(JSON.stringify({
    first:first.consumerLease,second:second.consumerLease,missing,unknown
}));
""", requests=True)
        self.assertEqual(result, {"first": "a" * 32 + ":1", "second": "a" * 32 + ":2",
                                  "missing": None, "unknown": None})

    def test_native_preparation_diagnostic_revision_matches_its_published_state(self):
        result = self.run_inventory("""
probe.reconcileTargetConsumers(snapshot);
Object.assign(probe,{targetProbe:true,revision:10,capable:true,refusal:-1,selfOwner:':1.1',
                    identityName:'alias',competingProviderRejected:true});
const writer={arguments:[],call:()=>{}},records=[];
console.info=(name,row)=>{if(name==='layout-probe-target') records.push(JSON.parse(row));};
probe.publish('online',[{id:8,consumer:'b',request:1,intent:'query'},
                      request(7,'a',probe.targetConsumerFor(7,'a').lease,2)],probe.readOwner);
const text=writer.arguments[0];
const packets=JSON.parse(text.slice('var messages = '.length,text.indexOf(';var written=0;')));
process.stdout.write(JSON.stringify({
    native:records[0].revision,packet:JSON.parse(packets[1].packet).revision
}));
""", requests=True)
        self.assertEqual(result, {"native": 12, "packet": 12})

    def run_consumer(self, action):
        script = """
console.info=()=>{};
const epoch='a'.repeat(32),lease=epoch+':1';
const context={epoch,generation:7,desktopId:'desktop',activityId:'activity',
               outputName:'Virtual-0',consumerLease:lease};
const deferred=[];
const Qt={callLater:callback=>deferred.push(callback)};
const Screen={name:'Virtual-0'};
const Plasmoid={configuration:{layoutRequest:'',writeConfig:()=>{}}};
const DBus={SessionBus:{asyncCall:()=>{}}};
const deadlineFactory={createObject:()=>({interval:10000,start:()=>{},stop:()=>{},destroy:()=>{}})};
const probe={
    stopped:false,targetEnabled:true,boot:'current',requestNumber:1,queryIntent:'query',
    requestOutput:'Virtual-0',requestContext:null,preparedContext:null,preparedToken:'',
    preparedReady:false,targetContext:{...context},targetPreparationPending:false,
    pendingMenuContext:null,focusPopupOpen:false,queryDeadline:null,queryTimeoutMs:10000,
    boundEpoch:'',boundOwner:'',boundIdentity:'',pendingPacket:null,revision:-1,accepted:0,
    phase:'online',epoch:'',observe:()=>{}
};
const packet={request:1,epoch,revision:1,status:'online',capable:true,backendOwner:':1.0',
              identityName:'alias',targetContext:{...context}};
const methods=(function(){with(probe){return {
"""
        methods = ("acceptPacket", "freshQuery", "stopQueryDeadline", "sendQuery",
                   "openTargetMenu", "requestTarget")
        script += ",".join(name + ":" + qml_handler(name) for name in methods)
        script += "};}})();Object.assign(probe,methods);\n" + action
        result = subprocess.run(["node", "-"], input=script, capture_output=True, text=True,
                                timeout=10, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_consumer_freezes_the_lease_before_opening_and_sends_that_original_lease(self):
        result = self.run_consumer("""
probe.openTargetMenu();
probe.targetContext.consumerLease='new-context';
const sentBefore=Plasmoid.configuration.layoutRequest;
probe.requestTarget('prepare');
probe.targetContext.consumerLease='changed-again';
deferred.shift()();
const outbound=JSON.parse(Plasmoid.configuration.layoutRequest);
process.stdout.write(JSON.stringify({
    sentBefore,pending:probe.pendingMenuContext,original:probe.requestContext.consumerLease,
    outgoing:outbound.consumerLease,request:outbound.request
}));
""")
        self.assertEqual(result, {"sentBefore": "", "pending": None, "original": "a" * 32 + ":1",
                                  "outgoing": "a" * 32 + ":1", "request": 2})

    def test_consumer_validation_uses_the_accepted_lease_not_a_later_context(self):
        result = self.run_consumer("""
probe.requestContext={...context,generation:6};
probe.acceptPacket({...packet,preparation:{intent:'prepare',ready:true,token:'prepared'}});
packet.targetContext.consumerLease='changed-packet';
probe.targetContext.consumerLease='new-context';
probe.requestTarget('validate');
deferred.shift()();
const outbound=JSON.parse(Plasmoid.configuration.layoutRequest);
process.stdout.write(JSON.stringify({
    original:probe.requestContext.consumerLease,accepted:probe.preparedContext.consumerLease,
    outgoing:outbound.consumerLease,token:outbound.token
}));
""")
        self.assertEqual(result, {"original": "a" * 32 + ":1", "accepted": "a" * 32 + ":1",
                                  "outgoing": "a" * 32 + ":1", "token": "prepared"})

    def test_missing_or_malformed_lease_cannot_establish_preparation_readiness(self):
        for invalid in (None, "", 3, [], {}, "x" * 129):
            with self.subTest(invalid=invalid):
                result = self.run_consumer("""
packet.targetContext.consumerLease=INVALID;
probe.acceptPacket({...packet,preparation:{intent:'prepare',ready:true,token:'prepared'}});
process.stdout.write(JSON.stringify({
    context:probe.targetContext,ready:probe.preparedReady,captured:probe.preparedContext
}));
""".replace("INVALID", json.dumps(invalid)))
                self.assertEqual(result, {"context": None, "ready": False, "captured": None})

    def test_validation_readiness_needs_the_original_accepted_consumer_lease(self):
        result = self.run_consumer("""
probe.acceptPacket({...packet,preparation:{intent:'prepare',ready:true,token:'prepared'}});
probe.acceptPacket({...packet,revision:2,targetContext:{...context,consumerLease:'new-lease'},
                    preparation:{intent:'validate',ready:true,token:'prepared'}});
process.stdout.write(JSON.stringify({ready:probe.preparedReady,
    captured:probe.preparedContext.consumerLease,current:probe.targetContext.consumerLease
}));
""")
        self.assertEqual(result, {"ready": False, "captured": "a" * 32 + ":1",
                                  "current": "new-lease"})

    def run_consumer_checker(self, fault=None):
        source = Path(__file__).with_name("scenario-bridge.sh").read_text()
        checker = source.split("# Consumer retirement receipt:", 1)[1]
        checker = checker.split("<<'PY'\n", 1)[1].split("\nPY\n", 1)[0]
        packet = {"consumer": "current", "request": 3, "revision": 17,
                  "targetContext": {"consumerLease": "provider:2"},
                  "preparation": {"intent": "prepare", "ready": False, "reason": "busy", "token": ""}}
        observation = {"boot": "current", "request": 3, "phase": "online", "packet": packet}
        query = {"boot": "current", "request": 3}
        native = {"consumer": "current", "request": 3, "revision": 17, "intent": "prepare",
                  "ready": False, "reason": "busy", "targetAlive": False, "targetClass": ""}
        if fault == "old-state":
            packet["revision"] = 16
        elif fault == "wrong-receiver":
            packet["consumer"] = "other"
        elif fault == "wrong-native-revision":
            native["revision"] = 16
        elif fault == "wrong-native-reason":
            native["reason"] = "stale-context"
        elif fault == "missing-lease":
            packet["targetContext"] = None
        events = [("query", query), ("observation", observation)]
        if fault == "received-not-accepted":
            events[-1] = ("received", observation)
        elif fault == "out-of-order":
            events.reverse()
        with tempfile.TemporaryDirectory(prefix="pf-consumer-check-", dir="/tmp/opencode") as scratch:
            root = Path(scratch)
            shell = root / "shell.log"
            shell.write_text("".join(
                f"qml: layout-probe-{kind} {json.dumps(row)}\n" for kind, row in events
            ))
            backend = root / "kwin.log"
            backend.write_text("qml: layout-probe-target " + json.dumps(native) + "\n")
            return subprocess.run(
                [sys.executable, "-", str(shell), str(backend), "current", "16", "prepare",
                 "false", "busy", "-", str(root / "current.json")],
                input=checker, capture_output=True, text=True, timeout=10, check=False,
            )

    def test_consumer_receipt_correlates_accepted_state_and_exact_native_revision(self):
        result = self.run_consumer_checker()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_consumer_receipt_rejects_old_unaccepted_or_mismatched_evidence(self):
        for fault in ("old-state", "wrong-receiver", "wrong-native-revision", "wrong-native-reason",
                      "missing-lease", "received-not-accepted", "out-of-order"):
            with self.subTest(fault=fault):
                self.assertNotEqual(self.run_consumer_checker(fault).returncode, 0)


if __name__ == "__main__":
    unittest.main()
