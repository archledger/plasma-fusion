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
// not count.
Item {
    id: layoutState

    // The bar's output by name. A request names it, and a change asks again.
    property string outputName: ""
    // The saved answer: the clock's layoutResponse field once its schema declares one.
    property string response: ""

    // The current request's outcome - idle (no output to ask for), pending, answered or refused -
    // kept apart from the state an answer gives.
    readonly property string outcome: d.outcome
    readonly property bool capable: d.answer !== null && d.answer.capable
    readonly property var view: d.answer !== null ? d.answer.view : null
    readonly property bool tiled: d.answer !== null && d.answer.tiled
    readonly property string refusal: d.refusal
    readonly property string epoch: d.bound !== null ? d.bound.epoch : ""
    readonly property int revision: d.revision
    // The mode for this bar's view: unknown until an answer is taken, unavailable when the
    // provider cannot tile or KWin has no such output.
    readonly property string mode: outcome !== "answered" ? "unknown"
        : !capable || view === null ? "unavailable" : tiled ? "tiled" : "floating"

    // The request to save. The handler writes it to the clock's layoutRequest field and saves the
    // configuration before it returns, so the wake that follows finds the request saved.
    signal requested(string text)

    QtObject {
        id: d

        readonly property string consumer: Qt.md5(Date.now() + ":" + Math.random() + ":" + Math.random())
        readonly property string identityPrefix: "org.plasmafusion.LayoutProvider.p"
        readonly property string wakeShortcut: "Plasma Fusion: Refresh Layout Controls"
        property int request: 0
        property string requestedOutput: ""
        property string outcome: "idle"
        // The accepted online answer to the current request, and its refusal when it was refused.
        property var answer: null
        property string refusal: ""
        property int revision: 0
        // The lifetime (epoch, owner, identity) whose frames the current request takes.
        property var bound: null
        // The newest well-formed frame waiting for its check on the bus.
        property var pending: null
        property bool verifying: false
        property bool started: false
        property bool stopped: false
        // Whether the component still lives, kept apart from it: a reply from the bus can come
        // after the component is gone, and must then touch nothing of it.
        property var life: ({ alive: true })
    }

    // A new request for the bar's output: the state is unknown at once, until its answer comes.
    // Each call retires the request that was out, even with nothing to ask for, so that no answer
    // to it - a late one, or one being checked - counts.
    function ask(): void {
        d.answer = null;
        d.refusal = "";
        d.revision = 0;
        d.bound = null;
        d.pending = null;
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
        d.request += 1;
        d.requestedOutput = outputName;
        d.outcome = "pending";
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

    function send(number: int): void {
        if (d.stopped || number !== d.request) {
            return;
        }
        requested(JSON.stringify({ version: 1, intent: "query", consumer: d.consumer, request: number,
                                   outputName: d.requestedOutput }));
        DBus.SessionBus.asyncCall({
            service: "org.kde.kglobalaccel", path: "/component/kwin",
            iface: "org.kde.kglobalaccel.Component", member: "invokeShortcut",
            arguments: [d.wakeShortcut]
        }, () => {}, reply => console.warn("plasmafusion-clockpill: layout state: the wake failed:",
                                           reply.error.name));
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
        verify();
    }

    // Asks the bus for the unique name of the connection that owns a name. A failed lookup ends
    // the check and confirms nothing, and a reply after the component is gone touches nothing.
    function ownerOf(name: string, done: var): void {
        const life = d.life;
        DBus.SessionBus.asyncCall({
            service: "org.freedesktop.DBus", path: "/org/freedesktop/DBus",
            iface: "org.freedesktop.DBus", member: "GetNameOwner", arguments: [name]
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
        if (frame.revision <= d.revision) {
            return;
        }
        d.bound = { epoch: frame.epoch, owner: frame.backendOwner, identity: frame.identityName };
        if (frame.status === "offline") {
            // The lifetime is going: unknown until whatever comes next answers a new request.
            ask();
            return;
        }
        d.revision = frame.revision;
        if (frame.refused !== undefined) {
            d.answer = null;
            d.refusal = frame.refused;
            d.outcome = "refused";
            return;
        }
        d.answer = { capable: frame.capable, view: frame.view, tiled: frame.tiled };
        d.refusal = "";
        d.outcome = "answered";
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
