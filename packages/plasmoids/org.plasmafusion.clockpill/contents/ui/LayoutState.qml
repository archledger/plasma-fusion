// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import org.kde.plasma.workspace.dbus as DBus

// The bar's tiling state as the placement script's layout provider tells it (docs/parts/kwin.md,
// "The layout provider's state"; docs/parts/shell-topbar.md, "Workspace layout state"). The bar
// asks for the view of its own output and takes only an answer to its current request, checked
// on the session bus: the connection that owns org.kde.KWin must also own the answering lifetime's
// identity name. Until such an answer comes the state is unknown. A saved answer alone is never
// state: every instance asks as a consumer of its own, so an answer kept from an earlier one does
// not count. The bus says when the answering lifetime's names leave its connection, and the bar is
// then unknown again.
// It also carries the bar's layout action (docs/parts/shell-topbar.md, "The layout action", whose
// table names the rows T1 to T36 cited below): the layout menu's Floating and Tiled choices, sent
// to the provider as a prepare and a set, whose outcomes come back in the same frames. The menu's
// owner forwards the user's input to open(), input(), choose() and close() and binds to the
// action's state; the decisions are made here. Each input, frame or deadline decides first and
// then changes each property at most once.
Item {
    id: layoutState

    // The bar's output by name. A request names it, and a change asks again.
    property string outputName: ""
    // The saved answer: the clock's layoutResponse field once its schema declares one.
    property string response: ""
    // How long a request waits for its answer, in ms: 100 to 10000, and 10000 for anything else.
    // A request keeps the deadline it was made with; a change applies from the next request.
    property int deadlineMs: 10000

    // The current request's outcome - idle (no output to ask for), pending, unconfirmed (past its
    // deadline with no answer, and still out), answered or refused - kept apart from the state an
    // answer gives.
    readonly property string outcome: d.outcome
    readonly property bool capable: d.answer !== null && d.answer.capable
    readonly property var view: d.answer !== null ? d.answer.view : null
    readonly property bool tiled: d.answer !== null && d.answer.tiled
    readonly property string refusal: d.refusal
    readonly property string epoch: d.bound !== null ? d.bound.epoch : ""
    readonly property int revision: d.revision
    // The mode for this bar's view, from the answer held: unknown until one is taken, unavailable
    // when the provider cannot tile or KWin has no such output. A query drops the answer it
    // replaces, so it starts unknown; an intent keeps it until its own first frame or its
    // deadline, so the mode stays on screen while the menu waits for the provider.
    readonly property string mode: d.answer === null ? "unknown"
        : !capable || view === null ? "unavailable" : tiled ? "tiled" : "floating"

    // The layout action. It is available while a mode shows and the answering lifetime has not
    // refused the intents as the bar sends them, which it would do to every further choice too.
    // Its state is idle (no action, or one ended with nothing awaited), open (nothing in flight:
    // the next input prepares), preparing (the prepare is out), prepared (done and ready: a choice
    // sends the set), setting (the set is out, the menu open) or awaiting (the menu closed, the
    // set awaited until its deadline); the menu shows only while the action is open.
    readonly property bool actionsAvailable: canAct(d.answer)
    readonly property bool actionOpen: menuShown(d.action)
    readonly property string actionState: d.action
    // The choice queued or sent, kept until the next request, so that an outcome presented after
    // it is still worded for its mode.
    readonly property string actionChoice: d.choice
    readonly property bool actionPending: d.queued !== "" || setOut(d.action)
    // The done prepare's handle and whether it found an app to tile, held only while prepared.
    readonly property string actionHandle: d.handle
    readonly property bool actionTarget: d.target
    // Tiled needs an app to make the master, unless the view is tiled already.
    readonly property bool tiledBlocked: d.action === "prepared" && !d.target
        && floatingView(d.answer)
    // What the menu or the pill presents, or empty: the provider's reason, or one of the bar's own
    // - unconfirmed (no answer by the deadline), interrupted (the menu closed by itself before its
    // set was read) and malformed (a frame without the intent's fields as the provider adds them).
    readonly property string actionReason: d.reason

    // The request to save. The handler writes it to the clock's layoutRequest field and saves the
    // configuration before it returns, so the wake that follows finds the request saved.
    signal requested(string text)
    // An outcome to present, with the mode it concerns (the choice then, or empty), emitted once
    // every property has its final value, so that a handler may read them. An empty reason clears
    // a notice: a done set.
    signal actionOutcome(string reason, string mode)

    QtObject {
        id: d

        readonly property string consumer: Qt.md5(Date.now() + ":" + Math.random() + ":" + Math.random())
        readonly property string identityPrefix: "org.plasmafusion.LayoutProvider.p"
        readonly property string wakeShortcut: "Plasma Fusion: Refresh Layout Controls"
        readonly property int deadlineInterval: layoutState.deadlineMs >= 100
            && layoutState.deadlineMs <= 10000 ? layoutState.deadlineMs : 10000
        property int request: 0
        property string requestedOutput: ""
        property string outcome: "idle"
        // The accepted online answer to the current request, and its refusal when it was refused.
        property var answer: null
        property string refusal: ""
        property int revision: 0
        // The lifetime (epoch, owner, identity) whose frames the current request takes.
        property var bound: null
        // The newest well-formed frame waiting for its check on the bus, and the frame being
        // checked while its check runs.
        property var pending: null
        property var checking: null
        property bool verifying: false
        property bool started: false
        property bool stopped: false
        // Whether the component still lives, kept apart from it: a reply from the bus can come
        // after the component is gone, and must then touch nothing of it.
        property var life: ({ alive: true })
        // The current request: its kind (query, prepare or set) and the fields it carries beside
        // its number; whether the current action sent it; whether a frame of it has been taken,
        // and its completion, which counts only once; for a set, whether its deadline passed
        // before its completion came; and whether it was made in the event now settling.
        property string kind: "query"
        property var message: null
        property bool own: false
        property bool taken: false
        property bool completed: false
        property bool late: false
        property bool renewed: false
        // The action: its state, the context frozen when it opened, the choice queued with the
        // prepare, the choice and the reason shown, the prepared handle and target, how the menu
        // closed (recorded once, as the action ends), and the lifetime that refused intents.
        property string action: "idle"
        property var frozen: null
        property string queued: ""
        property string choice: ""
        property string reason: ""
        property string handle: ""
        property bool target: false
        property bool userClosed: false
        property string refusedBy: ""
    }

    // A new request for the bar's output: the state is unknown at once, until its answer comes.
    // Asking again also ends the action, as the answer it acted on is gone, and a set that was out
    // is presented unconfirmed: no answer to it can count any more (T33). The action ends before
    // the mode goes, so that a close the mode's change makes - the control hiding - meets it ended.
    function ask(): void {
        const before = d.action;
        const awaited = setOut(d.action);
        moveAction("idle", false);
        query();
        settle(before, awaited ? "unconfirmed" : null);
    }

    // Each call retires the request that was out, even with nothing to ask for, so that no answer
    // to it - a late one, or one being checked - counts. Its deadline goes with it, and the new
    // request's starts here, so the old one's cannot end the new request's wait.
    function query(): void {
        beginRequest("query");
        d.answer = null;
        d.refusal = "";
        d.revision = 0;
        d.bound = null;
        if (d.stopped) {
            return;
        }
        if (d.request >= 2147483646) {
            d.stopped = true;
            d.requestedOutput = "";
            d.outcome = "idle";
            console.warn("plasmafusion-clockpill: layout state: no request numbers left");
            return;
        }
        if (outputName.length === 0 || outputName.length > 128) {
            if (d.outcome !== "idle") {
                d.request += 1;
            }
            d.requestedOutput = "";
            d.outcome = "idle";
            return;
        }
        d.requestedOutput = outputName;
        issue({ intent: "query", outputName: outputName }, "");
    }

    // A prepare or a set, numbered on from the queries with the same deadline rules, and `choice`
    // the choice it carries. Unlike a query it keeps the answer held, its lifetime and its
    // revision: the mode stays on screen until the intent's first frame or its deadline, and that
    // frame may come at the revision shown. False when no request number is left; the bar then
    // stops, as asking again does there.
    function intend(message: var, choice: string): bool {
        if (d.request >= 2147483646) {
            ask();
            return false;
        }
        beginRequest(message.intent);
        issue(message, choice);
        return true;
    }

    // What every new request begins with: the request it replaces loses its deadline and the frame
    // waiting for its check, and what the bar follows of a request starts afresh. Only the action
    // sends intents, so an intent is the current action's until the next one opens.
    function beginRequest(kind: string): void {
        deadline.stop();
        d.pending = null;
        d.kind = kind;
        d.own = kind !== "query";
        d.taken = false;
        d.completed = false;
        d.late = false;
    }

    // Makes `message` the current request, with a deadline of its own, and `choice` the choice
    // shown. The reason shown, which concerned the request before it, goes as the event settles.
    function issue(message: var, choice: string): void {
        d.request += 1;
        d.outcome = "pending";
        d.message = message;
        d.choice = choice;
        d.renewed = true;
        deadline.interval = d.deadlineInterval;
        deadline.start();
        const number = d.request;
        const life = d.life;
        // Leave whatever asked - a configuration change among them - before saving the request;
        // the call may come after the component is gone.
        Qt.callLater(() => {
            if (life.alive) {
                send(number);
            }
        });
    }

    // The request as the provider's reader copies it: a query names the output, a prepare also
    // the frozen context, and a set the mode and the prepared handle.
    function send(number: int): void {
        if (d.stopped || number !== d.request) {
            return;
        }
        const head = { version: 1, intent: d.message.intent, consumer: d.consumer,
                       request: number };
        requested(JSON.stringify(Object.assign(head, d.message)));
        wake();
    }

    // Wakes the provider, which reads only when woken: after each request, once its owner has saved
    // it (send), and for the owner after it withdraws its saved request, so that the provider forgets
    // the widget at once rather than at some other bar's wake.
    function wake(): void {
        DBus.SessionBus.asyncCall({
            service: "org.kde.kglobalaccel", path: "/component/kwin",
            iface: "org.kde.kglobalaccel.Component", member: "invokeShortcut", signature: "(s)",
            arguments: [d.wakeShortcut]
        }, () => {}, reply => console.warn("plasmafusion-clockpill: layout state: the wake failed:",
                                           reply.error.name));
    }

    // Opens an action for the menu, freezing the context it acts on from the answer held - the
    // lifetime, the view and the output - and sends nothing, so a menu opened and closed again
    // holds nothing of the provider's. False, changing nothing, unless the bar is idle with actions
    // available: while a set is awaited the control's activation is ignored (T1, T2).
    function open(): bool {
        if (d.action !== "idle" || !canAct(d.answer)) {
            return false;
        }
        const view = d.answer.view;
        d.frozen = { epoch: d.bound.epoch, outputName: d.requestedOutput,
                     view: { desktopId: view.desktopId, activityId: view.activityId } };
        // The new action has sent nothing: what is still out is an earlier action's (T35).
        d.own = false;
        moveAction("open", false);
        settle("idle", null);
        return true;
    }

    // The menu's input that counts - a navigation or choosing key, or a press on a row - prepares
    // an open action (T3); anywhere else it is ignored (T36). It waits for one rather than for the
    // open: the provider has one prepared slot for all the bars, so while one holds it a prepare
    // from any other is refused busy.
    function input(): void {
        if (d.action === "open") {
            prepare("");
        }
    }

    // The user's choice, tiled or floating: queued with a prepare while nothing is prepared, and
    // sent once prepared. A choice while one is queued or a set is out, Tiled while it is blocked,
    // and anything that names no mode are ignored (T36).
    function choose(mode: string): void {
        if (mode !== "tiled" && mode !== "floating") {
            return;
        }
        if (d.action === "open") {
            prepare(mode); // T4
        } else if (d.action === "preparing" && d.queued === "") {
            d.queued = mode; // T6
            d.choice = mode;
        } else if (d.action === "prepared" && sendable(mode, d.target, d.answer)) {
            if (sendSet(mode, d.handle)) {
                moveAction("setting", false); // T18
            }
            settle("prepared", null);
        }
    }

    // The menu closed, `dismissed` when the user closed it: Escape, or a press on the control. An
    // open action ends (T20), and a set already out stays awaited (T21). Once the action has ended
    // only the user's close counts: a press on the control that the menu's own hide came before
    // makes the close the user's, while the set is awaited or, past its deadline, still unread
    // (T22). Every other close changes nothing (T22a), among them the close(false) of the menu's
    // hide that follows every end of the action, even from inside the call that ended it.
    function close(dismissed: bool): void {
        const before = d.action;
        if (d.action === "setting") {
            moveAction("awaiting", dismissed); // T21
        } else if (menuShown(d.action)) {
            moveAction("idle", dismissed); // T20
        } else {
            if (dismissed && (d.action === "awaiting" || (d.kind === "set" && !d.taken))) {
                d.userClosed = true; // T22; any other close is T22a
            }
            return;
        }
        settle(before, null);
    }

    function prepare(choice: string): void {
        const frozen = d.frozen;
        const view = { desktopId: frozen.view.desktopId, activityId: frozen.view.activityId };
        if (!intend({ intent: "prepare", outputName: frozen.outputName, epoch: frozen.epoch,
                      view: view }, choice)) {
            return;
        }
        moveAction("preparing", false);
        d.queued = choice;
        settle("open", null);
    }

    // The set for `mode` with the prepare's handle. The menu stays open until the provider has read
    // it: a close first would end the preparation the handle names.
    function sendSet(mode: string, handle: string): bool {
        const outputName = d.frozen.outputName;
        return intend({ intent: "set", outputName: outputName, mode: mode, handle: handle }, mode);
    }

    // What a prepared action can send: Floating, or Tiled with an app to tile or on a tiled view.
    // Re-selecting the mode shown is sent too: the provider decides, not a mode that may lag it.
    function sendable(mode: string, target: bool, answer: var): bool {
        return mode === "floating" || target || (answer !== null && answer.tiled);
    }

    // The action's decisions read the state itself, never the properties bound to it: a call can
    // come from inside a change those properties notify - the menu's hide, as the action ends -
    // before each of them has followed it.
    function menuShown(action: string): bool {
        return action === "open" || action === "preparing" || action === "prepared"
            || action === "setting";
    }

    // A set is out, with the menu open or closed.
    function setOut(action: string): bool {
        return action === "setting" || action === "awaiting";
    }

    // The provider's reasons that say the action's view or shell is gone.
    function viewGone(why: string): bool {
        return why === "view-changed" || why === "shell-replaced";
    }

    // A mode shows, tiled or floating, from a lifetime that has not refused intents.
    function canAct(answer: var): bool {
        return answer !== null && answer.capable && answer.view !== null && d.bound !== null
            && d.bound.epoch !== d.refusedBy;
    }

    function floatingView(answer: var): bool {
        return answer !== null && answer.capable && answer.view !== null && !answer.tiled;
    }

    // Where the action is left once `answer` leaves nothing to act on - no mode shown, or a
    // lifetime that refused intents: an open action ends, and a set already out stays awaited
    // (T34).
    function withoutActions(action: string, answer: var): string {
        if (!menuShown(action) || canAct(answer)) {
            return action;
        }
        return action === "setting" ? "awaiting" : "idle";
    }

    // Moves the action to `next`. A move that ends the action records first how the menu closed:
    // the change hides the menu, whose hide calls close(false) at once, possibly from inside this
    // call, and that call must meet the ended action; no later move overwrites the record. The
    // queued choice, which only a prepare in flight holds, and the handle, which only a prepared
    // action may use, go after the state, so that the pending flag and Tiled's block, which read
    // them with the state, change once.
    function moveAction(next: string, dismissed: bool): void {
        if (menuShown(d.action) && (next === "idle" || next === "awaiting")) {
            d.userClosed = dismissed;
        }
        d.action = next;
        d.queued = "";
        if (next !== "prepared") {
            d.handle = "";
            d.target = false;
        }
    }

    // The end of an event, once every other property is final: an outcome to present becomes the
    // reason shown and is said with the mode it concerns; otherwise a change of state, or a
    // request made in the event, clears the reason.
    function settle(before: string, shown: var): void {
        const renewed = d.renewed;
        d.renewed = false;
        if (shown !== null) {
            d.reason = shown;
            actionOutcome(shown, d.choice);
        } else if (d.action !== before || renewed) {
            d.reason = "";
        }
    }

    // The current request's wait for its answer (P0's receipt, item 9). When it ends with the
    // request still pending, the outcome is unconfirmed, and the request stays out: a late answer
    // counts, and nothing is cancelled, renumbered or asked again. Under a Kiosk policy that
    // refuses the shell's scripting, or with no provider at all, no answer comes, so the bar ends
    // unconfirmed and its mode unknown.
    // Each new request stops the wait before it starts its own, and a QML Timer stopped or
    // restarted before its trigger is delivered does not deliver it (QQmlTimer::event, Qt 6.11), so
    // an earlier request's wait cannot end a later one's.
    Timer {
        id: deadline
        onTriggered: layoutState.expired()
    }

    // The current request's deadline. An intent with no frame by then drops the mode it kept, as
    // a query past its deadline shows none: the request may never have been read, and the view
    // may have changed since. The action moves before the mode goes, as in ask().
    function expired(): void {
        const before = d.action;
        const expiring = d.outcome === "pending";
        let next = before;
        let shown = null;
        if (before === "preparing") {
            // A prepare's first frame always carries its completion, so this one has had none
            // (T17, T17a).
            next = "idle";
            shown = "unconfirmed";
        } else if (setOut(before)) {
            // With frames but no completion, while the tiler retried its start, the mode stays and
            // an open menu takes a new choice, a new intent rather than a retry, unless the newest
            // frame names another view (T31, then T5); with no frame the action ends (T30). A late
            // completion still counts until the next request (T32).
            d.late = true;
            next = d.taken && before === "setting" && !movedFrom(d.answer.view) ? "open" : "idle";
            shown = "unconfirmed";
        } else {
            // An earlier action's prepare that went unread: an action opened again since has
            // nothing left to act on once the mode goes (T17b, then T34).
            next = withoutActions(before, expiring ? null : d.answer);
        }
        moveAction(next, false);
        if (expiring) {
            d.outcome = "unconfirmed";
            d.answer = null;
        }
        settle(before, shown);
    }

    // The response as a frame answering the current request, or null for anything else: the
    // provider's version-1 frame, online with its state or its refusal, or offline. Its owner, a
    // unique connection name, is the bus's to confirm (verify), and a revision counts only above
    // the request's floor (accept).
    function parsed(text: string): var {
        if (d.request === 0 || text.length === 0 || text.length > 4096) {
            return null;
        }
        let frame = null;
        try {
            frame = JSON.parse(text);
        } catch (e) {
            return null;
        }
        if (frame === null || typeof frame !== "object" || Array.isArray(frame) || frame.version !== 1
                || frame.consumer !== d.consumer || frame.request !== d.request
                || typeof frame.epoch !== "string" || !/^[0-9a-f]{32}$/.test(frame.epoch)
                || frame.identityName !== d.identityPrefix + frame.epoch
                || typeof frame.backendOwner !== "string" || !/^:[0-9]+\.[0-9]+$/.test(frame.backendOwner)
                || !Number.isInteger(frame.revision) || frame.revision > 2147483646) {
            return null;
        }
        if (frame.status === "offline") {
            return frame.capable === false && frame.view === null && frame.tiled === false
                && frame.refused === undefined ? frame : null;
        }
        if (frame.status !== "online") {
            return null;
        }
        if (frame.refused !== undefined) {
            return typeof frame.refused === "string" && frame.refused.length > 0
                && frame.refused.length <= 64 ? frame : null;
        }
        if (typeof frame.capable !== "boolean" || typeof frame.tiled !== "boolean" || !ownView(frame.view)
                || (frame.tiled && (!frame.capable || frame.view === null))) {
            return null;
        }
        return frame;
    }

    // An answer's view: none, for an output KWin does not have, or the requested output's desktop
    // and activity (the activity may be empty).
    function ownView(view: var): bool {
        return view === null || (typeof view === "object"
            && typeof view.desktopId === "string" && view.desktopId.length > 0 && view.desktopId.length <= 128
            && typeof view.activityId === "string" && view.activityId.length <= 128
            && view.outputName === d.requestedOutput);
    }

    // One check on the bus at a time; frames come in any order meanwhile, so only the newest of
    // one lifetime waits.
    function verify(): void {
        if (d.stopped || d.verifying || d.pending === null) {
            return;
        }
        const frame = d.pending;
        d.pending = null;
        d.verifying = true;
        d.checking = frame;
        ownerOf("org.kde.KWin", kwin => {
            if (kwin !== frame.backendOwner) {
                verified();
                return;
            }
            if (frame.status === "offline") {
                // A lifetime says it is going as it releases its identity name, so the name proves
                // nothing then: an offline frame counts only from the lifetime the request is bound to.
                if (d.bound !== null && d.bound.owner === frame.backendOwner
                        && d.bound.identity === frame.identityName) {
                    accept(frame);
                }
                verified();
                return;
            }
            ownerOf(frame.identityName, identity => {
                if (identity === frame.backendOwner) {
                    accept(frame);
                }
                verified();
            });
        });
    }

    // The check is over; the frame that waited, if one did, is checked next.
    function verified(): void {
        d.verifying = false;
        d.checking = null;
        verify();
    }

    // Asks the bus for the unique name of the connection that owns a name. A failed lookup ends
    // the check and confirms nothing, and a reply after the component is gone touches nothing.
    // The signature spares the plugin an introspection round trip before each lookup.
    function ownerOf(name: string, done: var): void {
        const life = d.life;
        DBus.SessionBus.asyncCall({
            service: "org.freedesktop.DBus", path: "/org/freedesktop/DBus",
            iface: "org.freedesktop.DBus", member: "GetNameOwner", signature: "(s)",
            arguments: [name]
        }, reply => {
            if (life.alive) {
                done(String(reply.value));
            }
        }, () => {
            if (life.alive) {
                verified();
            }
        });
    }

    function accept(frame: var): void {
        // The request may have moved on while the bus was asked.
        if (d.stopped || frame.request !== d.request) {
            return;
        }
        if (d.bound !== null && frame.epoch !== d.bound.epoch) {
            // Another provider lifetime: its revisions do not continue the one this request was
            // told, so the bar asks it afresh.
            ask();
            return;
        }
        // A query starts from no revision. An intent keeps the revision shown, and a done prepare
        // moves none, so the intent's first frame may come at that revision; every later frame
        // must be newer, so a frame the provider writes again is taken once.
        const unread = !d.taken;
        if (frame.revision < d.revision
                || (frame.revision === d.revision && (d.kind === "query" || !unread))) {
            return;
        }
        d.bound = { epoch: frame.epoch, owner: frame.backendOwner, identity: frame.identityName };
        if (frame.status === "offline") {
            // The lifetime is going: unknown until whatever comes next answers a new request.
            ask();
            return;
        }
        if (takeIntentRefusal(frame)) {
            return;
        }
        const answer = frame.refused !== undefined ? null
            : { capable: frame.capable, view: frame.view, tiled: frame.tiled };
        d.revision = frame.revision;
        d.taken = true;
        const before = d.action;
        const decision = frameDecision(frame, unread, answer);
        // The prepare's handle goes straight into the set, and is never held (T7).
        if (decision.set !== "" && !sendSet(decision.set, decision.handle)) {
            return;
        }
        // A frame whose mode leaves nothing to act on ends the action before the mode changes, so
        // that a close(false) the mode's change makes - the control hiding - meets the ended action
        // (T34). Any other frame gives the mode first, then the handle held and the move, so that
        // Tiled's block changes once.
        if (decision.lost) {
            moveAction(decision.next, false);
        }
        d.answer = answer;
        d.refusal = frame.refused !== undefined ? frame.refused : "";
        if (decision.set === "") {
            d.outcome = frame.refused !== undefined ? "refused" : "answered";
        }
        if (!decision.lost) {
            if (decision.hold) {
                d.handle = decision.handle;
                d.target = decision.target;
            }
            moveAction(decision.next, false);
        }
        settle(before, decision.shown);
    }

    // An intent the provider did not take as the bar sent it, decided before the frame's state is
    // held, as the bar asks again at once with a query, which starts unknown as every query does.
    // Refused at frame level, a waiting action ends with the reason (T16). Once the action has
    // ended, or for an open action's own intent after its decision, nothing is presented, and an
    // open action ends, as nothing is left to act on (T16a, then T34). Refused so, a prepared
    // action's frame, or one for an open action's own set still undecided past its deadline, gives
    // the mode only (T35a, then T34). A frame without the intent's fields ends a waiting or
    // prepared action with malformed (T15): dropping it would leave the bar to the deadline
    // whenever this provider answers so, and taking it as not ready would fail every further
    // choice.
    function takeIntentRefusal(frame: var): bool {
        if (d.kind === "query") {
            return false;
        }
        const before = d.action;
        const waiting = before === "preparing" || setOut(before);
        let shown = null;
        // What leaves the lifetime without actions, if anything.
        let failure = "";
        if (frame.refused !== undefined) {
            // T16a's: the intent's action has ended, or the open action's own intent is decided.
            const settled = before === "idle" || (before === "open" && (!d.own || d.completed));
            if (!waiting && !settled) {
                return false;
            }
            // Such a provider would refuse every further intent the same way; one that has no such
            // output refuses the bar's query too.
            const why = frame.refused;
            if (why === "intent" || why === "version" || why === "malformed") {
                failure = "refused the bar's " + d.kind + " at frame level with " + why;
            }
            shown = waiting ? why : null; // T16; T16a
        } else if ((waiting || before === "prepared") && !intentFieldsValid(frame)) { // T15
            failure = "sent a frame for the bar's " + d.kind + " that lacked the intent's fields";
            shown = "malformed";
        } else {
            return false;
        }
        // Ended first, as in ask(), and the lifetime marked then, so that the menu closes before
        // the actions go; the query, which lets the bound lifetime go, comes last.
        moveAction("idle", false);
        if (failure !== "") {
            markLifetime(failure);
        }
        query();
        settle(before, shown);
        return true;
    }

    // Leaves the lifetime that sent the frame without actions until another one answers, and says
    // which side failed. No intent goes to a lifetime so marked, so this is said once for it.
    function markLifetime(failure: string): void {
        d.refusedBy = d.bound.epoch;
        console.warn("plasmafusion-clockpill: layout state: the provider " + failure
                     + "; the layout actions are off for its lifetime " + d.bound.epoch);
    }

    // The action's rows for a taken frame of the current request, decided before anything changes.
    // In preparing, prepared, setting and awaiting the current request is the action's own: only
    // the action's requests lead there, and any other request ends the action first. Elsewhere a
    // frame gives the mode only (T35, T35a), but for a set's first completion after its deadline,
    // in idle or in the action that sent the set (T32). A completion counts once, from the first
    // frame that carries one, as every later frame of the request carries it again, the one each
    // desktop switch publishes among them.
    function frameDecision(frame: var, unread: bool, answer: var): var {
        // The frame's mode comes first: one that leaves nothing to act on ends the action before
        // its completion counts, so that no set goes out on it, and a set already out stays
        // awaited (T34).
        const state = withoutActions(d.action, answer);
        // An action that this frame ends was not closed by the user.
        const userClosed = !menuShown(d.action) && d.userClosed;
        const fresh = frame.refused === undefined && frame.completion !== undefined && !d.completed
            && intentFieldsValid(frame);
        if (fresh) {
            d.completed = true;
        }
        const prepared = frame.prepared;
        let decision = step(state, null);
        if (state === "preparing" && fresh) {
            decision = prepareDecided(frame.completion, prepared, answer); // T7 to T14, T19a
        } else if (state === "prepared" && prepared !== undefined && !prepared.ready) {
            // The one later field of a prepare's frames that counts (T11; T19, T19a).
            decision = step(viewGone(prepared.reason) ? "idle" : "open", null);
        } else if (setOut(state) && fresh) {
            decision = setDecided(frame.completion, unread, state, userClosed); // T24 to T29
        } else if (fresh && d.late && (d.action === "idle" || (d.action === "open" && d.own))) {
            decision = lateSetDecided(frame.completion, unread, state, userClosed); // T32
        }
        // A desktop switch or an activity change while the menu is open, which the next prepare
        // would find stale; a reason presented above stays presented (T5).
        if (decision.next === "open" && movedFrom(answer.view)) {
            decision.next = "idle";
        }
        decision.lost = state !== d.action;
        return decision;
    }

    // A row's decision: the state it leaves, the reason it presents (null for none), and for T7
    // the set to send with the prepare's handle, or for T8 and T9 the handle and target to hold.
    function step(next: string, shown: var): var {
        return { next: next, shown: shown, set: "", handle: "", target: false, hold: false,
                 lost: false };
    }

    // The prepare's first frame. Refused, the action stays open for the next input to prepare
    // again - silently for popup-focus-unconfirmed, which a choice made before KWin has seen the
    // popup's activation can cause - but for stale-context, whose context is gone. Done, the
    // preparation may already have ended; otherwise a queued choice that can be sent goes out with
    // the handle, or the action is prepared, presenting why Tiled is blocked when it is.
    function prepareDecided(completion: var, prepared: var, answer: var): var {
        if (completion.result === "refused") {
            const why = completion.reason;
            if (why === "stale-context") {
                return step("idle", why); // T14
            }
            return step("open", why === "popup-focus-unconfirmed" ? null : why); // T12, T12a; T13
        }
        if (!prepared.ready) {
            return step(viewGone(prepared.reason) ? "idle" : "open", null); // T11; T10, T19a
        }
        const decision = step("prepared", null);
        if (d.queued !== "" && sendable(d.queued, completion.target, answer)) {
            decision.next = "setting"; // T7
            decision.set = d.queued;
            decision.handle = completion.handle;
            return decision;
        }
        // Prepared, with why Tiled is blocked when it is (T8, T9).
        decision.shown = !completion.target && floatingView(answer) ? completion.reason : null;
        decision.hold = true;
        decision.handle = completion.handle;
        decision.target = completion.target;
        return decision;
    }

    // The set's completion before its deadline. Done ends the action and clears a notice: a done
    // Tiled gives the app focus, which hides the menu anyway (T24). Refused with the menu open, the
    // action stays open with the reason, unless the view or the shell changed (T26, T28; T27);
    // awaited, it ends (T25, T27, T29).
    function setDecided(completion: var, unread: bool, state: string, userClosed: bool): var {
        if (completion.result === "done") {
            return step("idle", ""); // T24
        }
        const why = completion.reason;
        if (state === "setting") {
            return step(viewGone(why) ? "idle" : "open", why); // T27; T26, T28
        }
        return step("idle", refusedAfterClose(why, unread, userClosed)); // T25, T27, T29
    }

    // The set's first completion after its deadline, while the set is still the current request:
    // done clears the notice and ends an open action, as a done set ends one; a refusal is
    // presented as it would have been while the set was awaited (T32).
    function lateSetDecided(completion: var, unread: bool, state: string, userClosed: bool): var {
        if (completion.result === "done") {
            return step("idle", "");
        }
        return step(state, refusedAfterClose(completion.reason, unread, userClosed));
    }

    // A set the menu's close came before. The close ended the preparation, so a set read after it
    // is refused stale-context, or focus-changed when KWin did not announce the change, in its
    // first frame: no news after the user's close, an interruption after any other (T25). Any
    // other refusal is its own reason.
    function refusedAfterClose(why: string, unread: bool, userClosed: bool): var {
        if (unread && (why === "stale-context" || why === "focus-changed")) {
            return userClosed ? null : "interrupted";
        }
        return why;
    }

    // Whether a view the provider names is not the one the action froze. Only an open action asks,
    // and an open action's answer shows a mode, so it names a view: one that does not ends the
    // action first (T34).
    function movedFrom(view: var): bool {
        const frozen = d.frozen.view;
        return view.desktopId !== frozen.desktopId || view.activityId !== frozen.activityId;
    }

    // Whether an intent's frame carries what the provider adds to it (docs/parts/kwin.md, "The
    // layout provider's state"): a prepare's completion, and while it is done its preparation with
    // the same handle; a set's completion once it has one, and never a preparation.
    function intentFieldsValid(frame: var): bool {
        const completion = frame.completion;
        const prepared = frame.prepared;
        if (d.kind === "set") {
            return prepared === undefined
                && (completion === undefined || completionValid(completion, frame.epoch));
        }
        if (completion === undefined || !completionValid(completion, frame.epoch)) {
            return false;
        }
        if (completion.result === "refused") {
            return prepared === undefined || preparationValid(prepared);
        }
        return prepared !== undefined && preparationValid(prepared)
            && prepared.handle === completion.handle;
    }

    // A completion for the current request's intent: done, or refused with its reason. A done
    // prepare's handle is the lifetime's (its epoch, then its serials), and its target says
    // whether it found an app to tile, with the reason when it did not.
    function completionValid(completion: var, epoch: string): bool {
        if (completion === null || typeof completion !== "object" || completion.intent !== d.kind) {
            return false;
        }
        if (completion.result === "refused") {
            return reasonValid(completion.reason);
        }
        if (completion.result !== "done") {
            return false;
        }
        return d.kind === "set" || (typeof completion.handle === "string"
            && completion.handle.length <= 128 && completion.handle.startsWith(epoch + ":")
            && typeof completion.target === "boolean"
            && (completion.target || reasonValid(completion.reason)));
    }

    function preparationValid(prepared: var): bool {
        return prepared !== null && typeof prepared === "object"
            && typeof prepared.ready === "boolean"
            && (prepared.ready || reasonValid(prepared.reason));
    }

    function reasonValid(reason: var): bool {
        return typeof reason === "string" && reason.length > 0 && reason.length <= 64;
    }

    // The bound lifetime is gone, with no frame, once its identity name or KWin's changes hands -
    // released, or handed straight to another connection - as its connection held both: the bar is
    // unknown and asks again, and whichever provider comes next reads the request saved.
    // A check needs one rule of its own. The lookups share this session connection with the
    // watch, and the bus says an owner changed before it answers any lookup made after, so a change
    // before a lookup fails it, and one after the check's answer is taken finds the lifetime bound.
    // But KWin's owner is looked up first and the identity's last: KWin's name moving from the
    // frame's owner between the two would let the check take a lifetime KWin no longer has, so
    // that, too, makes the bar ask again, which retires the request the check would answer. A move
    // the bus said just before the check began, and that reaches the bar while it runs, counts as
    // well: asking again is always safe.
    function nameMoved(name: string, previous: string): void {
        const bound = d.bound !== null && (name === d.bound.identity || name === "org.kde.KWin");
        const checked = d.checking !== null && name === "org.kde.KWin"
            && previous === d.checking.backendOwner;
        if (bound || checked) {
            ask();
        }
    }

    // Every change of a name's owner on the session bus, with both owners, so that a name handed
    // straight on is seen as well as one released; no polling.
    DBus.SignalWatcher {
        enabled: !d.stopped
        busType: DBus.BusType.Session
        service: "org.freedesktop.DBus"
        path: "/org/freedesktop/DBus"
        iface: "org.freedesktop.DBus"
        // The plugin hands strings over wrapped, so they are made strings first.
        function dbusNameOwnerChanged(name: var, previous: var, current: var): void {
            layoutState.nameMoved(String(name), String(previous));
        }
        // The bus says these to this connection about its own names and services; they say nothing
        // of the provider's lifetime.
        function dbusNameAcquired(name: var): void {
        }
        function dbusNameLost(name: var): void {
        }
        function dbusActivatableServicesChanged(): void {
        }
    }

    onOutputNameChanged: {
        if (d.started) {
            ask();
        }
    }
    onResponseChanged: {
        const frame = parsed(response);
        if (frame === null) {
            return;
        }
        const waiting = d.pending;
        if (waiting !== null && waiting.epoch === frame.epoch && waiting.backendOwner === frame.backendOwner
                && waiting.revision >= frame.revision) {
            return;
        }
        d.pending = frame;
        verify();
    }
    Component.onCompleted: {
        d.started = true;
        ask();
    }
    Component.onDestruction: {
        d.life.alive = false;
        d.stopped = true;
    }
}
