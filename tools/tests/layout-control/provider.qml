/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/
import QtQuick
import org.kde.kwin
import org.kde.plasma.workspace.dbus as DBus
import "Tiling.js" as Tiling

// Test-only provider. It never admits a window or writes geometry or placement records.
Item {
    id: probe
    property string epoch: "stock"
    property bool capable: false
    property int refusal: 0
    property int revision: 0
    property bool reading: false
    property bool again: false
    property string readOwner: ""
    property string replyOwner: ""
    property var recipients: []
    property bool focusProbe: false
    property bool targetProbe: false
    property bool mixedLifetimeProbe: false
    property bool viewLossProbe: false
    // Diagnostics for the view-loss case only: decisions never read these references.
    property var viewLossSubject: null
    // Bounded history of native output objects present at start or already reported.
    property var viewLossScreens: []
    property var lastEligibleWindow: null
    property int shellPid: 0
    property string shellPidOwner: ""
    property var preparedTarget: null
    property string preparationFailure: "not-prepared"
    property var targetExchange: null
    property int targetSerial: 0
    property int targetGeneration: 0
    property var lastFocusedWindow: null
    property var targetHandoff: null
    property var targetConsumers: []
    property int consumerSerial: 0
    property string inventoryOwner: ""
    property bool targetInventoryComplete: false
    property QtObject competingProvider: QtObject {}
    property bool competingProviderRejected: false
    property bool authorized: false
    property bool stopping: false
    property bool identityReady: false
    property string identityName: ""
    property string selfOwner: ""
    property var registration: null
    property bool registrationHandled: false
    property bool dropRetirementFrame: false
    property int replyDelayMs: 0
    property var pendingPublication: null

    Component {
        id: publicationFactory
        Timer {
            id: delayed
            required property var publisher
            required property string destination
            property var rows: []
            repeat: false
            triggeredOnStart: false
            onTriggered: {
                if (delayed.publisher.pendingPublication === delayed) {
                    delayed.publisher.pendingPublication = null;
                    if (!delayed.publisher.stopping) {
                        console.info("layout-probe: delayed publication released");
                        delayed.publisher.publish("online", delayed.rows, delayed.destination);
                    }
                }
                delayed.destroy();
            }
        }
    }

    function cancelPublication(): void {
        if (pendingPublication) {
            const timer = pendingPublication;
            pendingPublication = null;
            timer.stop();
            timer.destroy();
        }
    }

    function queuePublication(rows: var, destination: string): void {
        if (replyDelayMs === 0) {
            publish("online", rows, destination);
            return;
        }
        if (pendingPublication && pendingPublication.destination !== destination) {
            cancelPublication();
        }
        if (rows.length === 0) {
            return;
        }
        if (pendingPublication) {
            pendingPublication.rows = rows;
            return;
        }
        pendingPublication = publicationFactory.createObject(probe, {
            publisher: probe, destination: destination, rows: rows, interval: replyDelayMs
        });
        if (pendingPublication) {
            console.info("layout-probe: delayed publication queued", replyDelayMs);
            pendingPublication.start();
        } else {
            console.warn("layout-probe: cannot create private publication fault timer");
        }
    }

    function registrationFinished(): void {
        if (!registration || !registration.isFinished || registrationHandled || stopping) {
            return;
        }
        registrationHandled = true;
        // The workspace decoder returns a uint32 value wrapper, not a plain JS number.
        const granted = registration.isValid && registration.value.value === 1;
        const finished = registration;
        registration = null;
        finished.destroy();
        if (!granted) {
            console.warn("layout-probe: identity name not granted; transport stays unavailable");
            return;
        }
        identityLookup.arguments = [identityName];
        identityLookup.call();
    }
    onRegistrationChanged: registrationFinished()
    Connections {
        target: probe.registration
        function onFinished() { probe.registrationFinished(); }
    }
    DBusCall {
        id: identityLookup
        service: "org.freedesktop.DBus"
        path: "/org/freedesktop/DBus"
        dbusInterface: "org.freedesktop.DBus"
        method: "GetNameOwner"
        onFinished: value => {
            probe.selfOwner = String(value[0]);
            probe.identityReady = probe.selfOwner.startsWith(":");
            if (probe.identityReady) {
                probe.again = false;
                probe.scan();
            }
        }
    }
    DBusCall {
        id: identityRelease
        service: "org.freedesktop.DBus"
        path: "/org/freedesktop/DBus"
        dbusInterface: "org.freedesktop.DBus"
        method: "ReleaseName"
    }

    function providerAccepted(token: string): bool {
        // Qt's default UUID text includes braces, including for a refused/null UUID.
        const text = token.startsWith("{") && token.endsWith("}") ? token.slice(1, -1) : token;
        return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(text)
            && text !== "00000000-0000-0000-0000-000000000000";
    }

    function publish(status: string, rows: var, destination: string): void {
        if (!destination.startsWith(":") || rows.length === 0) {
            return;
        }
        const messages = rows.map(row => {
            const preparation = status === "online" && probe.targetProbe
                ? probe.handleTargetRequest(row) : null;
            if (preparation) {
                const window = probe.preparedTarget ? probe.preparedTarget.window : null;
                console.info("layout-probe-target", JSON.stringify({
                    consumer: row.consumer, request: row.request, intent: preparation.intent,
                    revision: revision + 1,
                    ready: preparation.ready, reason: preparation.reason,
                    targetClass: Tiling.alive(window) ? String(window.resourceClass) : "",
                    targetAlive: Tiling.alive(window)
                }));
            }
            if (probe.mixedLifetimeProbe) {
                console.info("layout-probe-published", JSON.stringify({
                    widget: row.id, destination: destination, consumer: row.consumer,
                    request: row.request, epoch: epoch, revision: revision + 1, status: status
                }));
            }
            return {id: row.id, packet: JSON.stringify({
                consumer: row.consumer, epoch: epoch, revision: ++revision,
                status: status, capable: capable, refusal: refusal,
                request: row.request,
                preparation: preparation,
                targetContext: status === "online" && probe.targetProbe
                    ? probe.captureTargetConsumerContext(row) : null,
                competingProviderRejected: competingProviderRejected,
                backendOwner: selfOwner, identityName: identityName
            })};
        });
        writer.service = destination;
        writer.arguments = ["var messages = " + JSON.stringify(messages) + ";var written=0;"
            + "panels().forEach(function(p) { p.widgets('org.plasmafusion.layoutprobe').forEach(function(w) {"
            + "messages.forEach(function(m) { if(w.id === m.id) { w.currentConfigGroup=['General'];"
            + "w.writeConfig('layoutResponse',m.packet); ++written; } }); }); });print(written);"];
        writer.call();
        console.info("layout-probe: publication", status, messages.length);
    }

    function scan(): void {
        if (!authorized || stopping) {
            return;
        }
        if (!identityReady) {
            again = true;
            return;
        }
        if (reading) {
            again = true;
            return;
        }
        reading = true;
        ownerLookup.call();
    }

    function traceFocus(event: string): void {
        if (!focusProbe || stopping) {
            return;
        }
        const active = Workspace.activeWindow;
        const remembered = lastEligibleWindow;
        const frame = Tiling.alive(remembered) ? remembered.frameGeometry : null;
        console.info("layout-probe-focus", JSON.stringify({
            event: event,
            activeClass: Tiling.alive(active) ? String(active.resourceClass) : "",
            activeEligible: Tiling.eligibleForMaster(active),
            activePid: Tiling.alive(active) ? Number(active.pid) : 0,
            activeDock: Tiling.alive(active) && active.dock === true,
            activeDesktop: Tiling.alive(active) && active.desktopWindow === true,
            activeAppletPopup: Tiling.alive(active) && active.appletPopup === true,
            activeNormal: Tiling.alive(active) && active.normalWindow === true,
            contextGeneration: targetGeneration,
            rememberedClass: Tiling.alive(remembered) ? String(remembered.resourceClass) : "",
            rememberedAlive: Tiling.alive(remembered),
            rememberedCenter: frame
                ? {x: frame.x + frame.width / 2, y: frame.y + frame.height / 2} : null,
            desktopId: Workspace.currentDesktop ? String(Workspace.currentDesktop.id) : "",
            activityId: String(Workspace.currentActivity),
            activeOutput: Workspace.activeScreen ? String(Workspace.activeScreen.name) : "",
            rememberedOutput: Tiling.alive(remembered) && remembered.output
                ? String(remembered.output.name) : ""
        }));
    }

    // One record per generation advance, naming the native event that caused it, so a broken
    // view handler cannot hide behind a focus change. An output is known only if the same native
    // object was present at start or in an earlier record; a same-name replacement is not.
    function traceView(reason: string, source: string, from: int, prepared: bool): void {
        if (!viewLossProbe || stopping) {
            return;
        }
        const active = Workspace.activeWindow;
        const subject = viewLossSubject;
        const alive = Tiling.alive(subject) && !!subject.output
            && Workspace.screens.indexOf(subject.output) >= 0;
        const frame = alive ? subject.frameGeometry : null;
        const known = viewLossScreens;
        console.info("layout-probe-view", JSON.stringify({
            reason: reason, source: source, from: from, generation: targetGeneration,
            prepared: prepared,
            screens: Workspace.screens.map(output => ({
                name: String(output.name), known: known.indexOf(output) >= 0,
                x: output.geometry.x, y: output.geometry.y,
                width: output.geometry.width, height: output.geometry.height
            })),
            activityId: String(Workspace.currentActivity), activities: Workspace.activities.length,
            desktopId: Workspace.currentDesktop ? String(Workspace.currentDesktop.id) : "",
            activeClass: Tiling.alive(active) ? String(active.resourceClass) : "",
            activeOutput: Tiling.alive(active) && active.output ? String(active.output.name) : "",
            subjectClass: alive ? String(subject.resourceClass) : "",
            subjectOutput: alive ? String(subject.output.name) : "",
            subjectFrame: frame
                ? {x: frame.x, y: frame.y, width: frame.width, height: frame.height} : null,
            subjectInView: alive && Tiling.onWorkspace(
                subject, Workspace.currentDesktopForScreen(subject.output),
                String(Workspace.currentActivity), subject.output)
        }));
        const added = Workspace.screens.filter(output => known.indexOf(output) < 0);
        viewLossScreens = known.concat(added).slice(-32);
    }

    // Native references never leave this object. The caller must resolve shellPid for readOwner
    // before preparation; a class/app-id string alone cannot identify a shell surface.
    function shellOwnsFocus(window: var, output: var): bool {
        return !!output && Tiling.alive(window) && shellPid > 0 && shellPidOwner === readOwner
            && window.pid === shellPid && window.output === output && !window.normalWindow
            && (window.appletPopup === true || window.dock === true || window.desktopWindow === true);
    }

    function invalidateTarget(reason: string): void {
        preparedTarget = null;
        preparationFailure = reason;
    }

    function targetContextReady(): bool {
        return authorized && capable && identityReady && !stopping
            && readOwner.startsWith(":") && shellPid > 0 && shellPidOwner === readOwner
            && targetGeneration >= 0 && lastFocusedWindow === Workspace.activeWindow;
    }

    function targetViewIsCurrent(view: var): bool {
        return Workspace.screens.indexOf(view.output) >= 0
            && Workspace.desktops.some(desktop => Tiling.desktopMatches(desktop, view.desktop))
            && view.activity !== "" && Workspace.activities.indexOf(view.activity) >= 0
            && Tiling.sameView(view, Workspace.currentDesktopForScreen(view.output),
                               String(Workspace.currentActivity), view.output);
    }

    function prepareTarget(outputName: string): bool {
        invalidateTarget("no-target");
        if (!targetContextReady()) {
            preparationFailure = "unavailable";
            return false;
        }
        const outputs = Workspace.screens.filter(output => String(output.name) === outputName);
        if (outputs.length !== 1) {
            preparationFailure = "view-unavailable";
            return false;
        }
        const output = outputs[0];
        const view = {
            output: output, desktop: Workspace.currentDesktopForScreen(output),
            activity: String(Workspace.currentActivity)
        };
        if (!view.desktop || !view.desktop.id || !targetViewIsCurrent(view)) {
            preparationFailure = "view-unavailable";
            return false;
        }
        const active = Workspace.activeWindow;
        const window = Tiling.eligibleForMaster(active) ? active
            : shellOwnsFocus(active, output) ? lastEligibleWindow : null;
        if (!Tiling.eligibleForMaster(window)
                || !Tiling.onWorkspace(window, view.desktop, view.activity, output)) {
            return false;
        }
        preparedTarget = {
            window: window, desktop: view.desktop, activity: view.activity, output: output,
            owner: readOwner, pid: shellPid, focusSurface: active
        };
        preparationFailure = "";
        return true;
    }

    function validateTarget(): bool {
        const saved = preparedTarget;
        if (!saved) {
            return false;
        }
        let reason = "";
        if (!targetContextReady() || saved.owner !== readOwner || saved.pid !== shellPid) {
            reason = "provider-context-changed";
        } else if (!targetViewIsCurrent(saved)) {
            reason = "view-changed";
        } else if (!Tiling.eligibleForMaster(saved.window)
                || !Tiling.onWorkspace(saved.window, saved.desktop, saved.activity, saved.output)) {
            reason = "target-departed";
        } else if (!Tiling.alive(saved.focusSurface) || Workspace.activeWindow !== saved.focusSurface
                || (saved.focusSurface !== saved.window
                    && !shellOwnsFocus(saved.focusSurface, saved.output))) {
            reason = "focus-changed";
        }
        if (reason !== "") {
            invalidateTarget(reason);
            return false;
        }
        return true;
    }

    function trackTargetActivation(window: var): void {
        const eligible = Tiling.eligibleForMaster(window);
        const shell = shellOwnsFocus(window, Tiling.alive(window) ? window.output : null);
        const previous = lastFocusedWindow;
        const candidate = lastEligibleWindow;
        const output = Tiling.alive(window) ? window.output : null;
        const opening = window !== previous && shell && window.appletPopup === true
            && Tiling.eligibleForMaster(candidate) && candidate.output === output
            && ((previous === candidate && Tiling.eligibleForMaster(previous))
                || (shellOwnsFocus(previous, output)
                    && (previous.dock === true || previous.desktopWindow === true)));
        const generation = targetGeneration;
        lastFocusedWindow = window;
        // Shell surfaces participate too, even before a preparation exists.
        if (window !== previous || (!eligible && !shell)) {
            advanceTargetContext("focus-changed", "activation");
        }
        if (opening && targetGeneration === generation + 1 && targetGeneration >= 0) {
            const handoff = {
                fromGeneration: generation, generation: targetGeneration,
                source: previous, popup: window, window: candidate, output: output,
                desktop: Workspace.currentDesktopForScreen(output),
                activity: String(Workspace.currentActivity)
            };
            if (targetViewIsCurrent(handoff)
                    && Tiling.onWorkspace(candidate, handoff.desktop, handoff.activity, output)) {
                targetHandoff = handoff;
            }
        }
        if (eligible) {
            lastEligibleWindow = window;
        } else if (!shell) {
            lastEligibleWindow = null;
        }
    }

    function targetViewChanged(source: string): void {
        lastEligibleWindow = null;
        advanceTargetContext("view-changed", source);
    }

    function targetMembershipChanged(source: string): void {
        lastEligibleWindow = null;
        advanceTargetContext("target-departed", source);
    }

    function targetEligibilityChanged(source: string): void {
        if (!Tiling.eligibleForMaster(lastEligibleWindow)) {
            targetMembershipChanged(source);
        }
    }

    function advanceTargetContext(reason: string, source: string): void {
        const from = targetGeneration;
        const prepared = preparedTarget !== null;
        targetHandoff = null;
        if (targetGeneration >= 0) {
            targetGeneration = targetGeneration < 2147483646 ? targetGeneration + 1 : -1;
        }
        invalidateTarget(reason);
        if (probe.targetProbe && !probe.stopping) {
            probe.traceFocus("context-changed");
            probe.traceView(reason, source, from, prepared);
            probe.scan();
        }
    }

    function canUseTargetHandoff(row: var): bool {
        const handoff = targetHandoff;
        return row.intent === "prepare" && !!handoff
            && handoff.fromGeneration === row.viewGeneration
            && handoff.generation === targetGeneration
            && handoff.generation === handoff.fromGeneration + 1
            && Tiling.alive(handoff.source) && handoff.window === lastEligibleWindow
            && Tiling.eligibleForMaster(handoff.window)
            && handoff.popup === lastFocusedWindow && handoff.popup === Workspace.activeWindow
            && shellOwnsFocus(handoff.popup, handoff.output) && handoff.popup.appletPopup === true
            && targetViewIsCurrent(handoff)
            && String(handoff.output.name) === row.outputName
            && String(handoff.output.name) === row.viewOutputName
            && String(handoff.desktop.id) === row.desktopId && handoff.activity === row.activityId
            && Tiling.onWorkspace(handoff.window, handoff.desktop, handoff.activity, handoff.output);
    }

    function targetConsumerFor(id: real, consumer: string): var {
        if (!targetInventoryComplete || inventoryOwner !== readOwner) {
            return null;
        }
        return targetConsumers.find(actor => actor.confirmed && actor.owner === readOwner
            && actor.id === id && actor.consumer === consumer) || null;
    }

    function captureTargetConsumerContext(row: var): var {
        const actor = targetConsumerFor(row.id, row.consumer);
        const context = actor ? captureTargetContext(row.outputName) : null;
        return context ? Object.assign(context, {consumerLease: actor.lease}) : null;
    }

    function consumeTargetInventory(snapshot: var): var {
        const ids = new Set();
        if (!snapshot || !Array.isArray(snapshot.widgets) || !Array.isArray(snapshot.rows)
                || snapshot.rows.length > 16 || snapshot.rows.some(row => {
                    if (!row || ids.has(row.id) || typeof row.consumer !== "string"
                            || !Number.isInteger(row.request) || row.request <= 0
                            || row.request > 2147483646 || !snapshot.widgets.some(widget =>
                                widget && widget.id === row.id && widget.consumer === row.consumer)) {
                        return true;
                    }
                    ids.add(row.id);
                    return false;
                }) || snapshot.widgets.some(widget => widget && widget.consumer !== null
                    && !ids.has(widget.id))) {
            reconcileTargetConsumers(null);
            return null;
        }
        return reconcileTargetConsumers(snapshot) ? snapshot.rows : null;
    }

    // Request parse failure is not widget absence. Only a complete native inventory may retire
    // identities; an unknown consumer keeps its prior lease inert until it is confirmed again.
    function reconcileTargetConsumers(snapshot: var): bool {
        targetInventoryComplete = false;
        targetConsumers.forEach(actor => { actor.confirmed = false; });
        if (!snapshot || snapshot.complete !== true || !Array.isArray(snapshot.widgets)
                || snapshot.widgets.length > 16 || !readOwner.startsWith(":")) {
            return false;
        }
        const ids = new Set();
        for (const widget of snapshot.widgets) {
            if (!widget || !Number.isInteger(widget.id) || widget.id <= 0
                    || widget.id > 4294967295 || ids.has(widget.id)
                    || (widget.consumer !== null && (typeof widget.consumer !== "string"
                        || widget.consumer.length === 0 || widget.consumer.length > 128))) {
                return false;
            }
            ids.add(widget.id);
        }
        const previous = inventoryOwner === readOwner ? targetConsumers : [];
        const additions = snapshot.widgets.filter(widget => widget.consumer !== null
            && !previous.some(actor => actor.id === widget.id && actor.consumer === widget.consumer));
        if (consumerSerial > 2147483646 - additions.length) {
            invalidateTarget("consumer-capacity");
            return false;
        }
        const current = [];
        for (const widget of snapshot.widgets) {
            const existing = previous.find(actor => actor.id === widget.id
                && (widget.consumer === null || actor.consumer === widget.consumer));
            if (existing) {
                existing.confirmed = widget.consumer !== null;
                current.push(existing);
            } else if (widget.consumer !== null) {
                current.push({
                    owner: readOwner, id: widget.id, consumer: widget.consumer,
                    lease: epoch + ":" + (++consumerSerial), confirmed: true,
                    request: 0, payload: "", outcome: "not-prepared"
                });
            }
        }
        if (targetExchange && !current.some(actor => actor.owner === targetExchange.owner
                && actor.id === targetExchange.id && actor.consumer === targetExchange.consumer
                && actor.lease === targetExchange.lease)) {
            targetExchange = null;
            invalidateTarget("consumer-retired");
        }
        targetConsumers = current;
        inventoryOwner = readOwner;
        targetInventoryComplete = true;
        return true;
    }

    function captureTargetContext(outputName: string): var {
        if (!targetContextReady()) {
            return null;
        }
        const outputs = Workspace.screens.filter(output => String(output.name) === outputName);
        if (outputs.length !== 1) {
            return null;
        }
        const output = outputs[0];
        const view = {
            output: output, desktop: Workspace.currentDesktopForScreen(output),
            activity: String(Workspace.currentActivity)
        };
        if (!view.desktop || !view.desktop.id || !targetViewIsCurrent(view)) {
            return null;
        }
        return {
            epoch: epoch, generation: targetGeneration, desktopId: String(view.desktop.id),
            activityId: view.activity, outputName: String(output.name)
        };
    }

    // One bounded diagnostic slot. Validation is read-only and always rechecks native state;
    // replaying a prepare must not capture a different window or renew an invalidated reference.
    function handleTargetRequest(row: var): var {
        if (row && (row.intent === undefined || row.intent === "query")) {
            return null;
        }
        const response = {intent: "invalid", ready: false, reason: "malformed", token: ""};
        if (!row || row.version !== 1 || !Number.isInteger(row.id) || row.id <= 0
                || typeof row.consumer !== "string" || row.consumer.length === 0
                || row.consumer.length > 128 || !Number.isInteger(row.request)
                || typeof row.consumerLease !== "string" || row.consumerLease.length === 0
                || row.consumerLease.length > 128
                || row.request <= 0 || row.request > 2147483646
                || (row.intent !== "prepare" && row.intent !== "validate")
                || typeof row.outputName !== "string" || row.outputName.length === 0
                || row.outputName.length > 128 || typeof row.token !== "string"
                || row.token.length > 128 || (row.intent === "prepare" && row.token !== "")
                || typeof row.viewEpoch !== "string" || row.viewEpoch.length > 128
                || !Number.isInteger(row.viewGeneration) || row.viewGeneration < 0
                || typeof row.desktopId !== "string" || row.desktopId.length > 128
                || typeof row.activityId !== "string" || row.activityId.length > 128
                || typeof row.viewOutputName !== "string" || row.viewOutputName.length > 128) {
            return response;
        }
        response.intent = row.intent;
        if (!targetContextReady()) {
            response.reason = "unavailable";
            return response;
        }
        const actor = targetConsumerFor(row.id, row.consumer);
        if (!actor || row.consumerLease !== actor.lease) {
            response.reason = "consumer-not-current";
            return response;
        }
        if (targetExchange && targetExchange.owner !== readOwner) {
            targetExchange = null;
            lastEligibleWindow = null;
            invalidateTarget("shell-replaced");
        }
        const payload = JSON.stringify([row.intent, row.outputName, row.token, row.viewEpoch,
                                        row.viewGeneration, row.desktopId, row.activityId,
                                        row.viewOutputName, row.consumerLease]);
        if (row.request < actor.request
                || (row.request === actor.request && payload !== actor.payload)) {
            response.reason = "stale-or-conflicting-request";
            return response;
        }
        const fresh = row.request > actor.request;
        if (fresh) {
            actor.request = row.request;
            actor.payload = payload;
            actor.outcome = "refused";
        } else if (row.intent === "prepare" && actor.outcome !== "prepared") {
            response.reason = actor.outcome;
            return response;
        }
        let exchange = targetExchange;
        if (exchange && (exchange.consumer !== row.consumer || exchange.id !== row.id
                || exchange.lease !== actor.lease)) {
            if (fresh) actor.outcome = "busy";
            response.reason = "busy";
            return response;
        }
        if (!exchange) {
            if (row.intent !== "prepare") {
                response.reason = "wrong-preparation";
                return response;
            }
            exchange = {owner: readOwner, consumer: row.consumer, id: row.id,
                        lease: actor.lease, outputName: "", nonce: ""};
            targetExchange = exchange;
        }
        if (fresh && row.intent === "prepare") {
            invalidateTarget("stale-context");
        }
        // Claim the bounded identity even on refusal: it must never become a later capture.
        const context = captureTargetContext(row.outputName);
        if (!context || row.viewEpoch !== context.epoch
                || (row.viewGeneration !== context.generation && !canUseTargetHandoff(row))
                || row.desktopId !== context.desktopId
                || row.activityId !== context.activityId || row.viewOutputName !== context.outputName) {
            response.reason = "stale-context";
            return response;
        }
        const active = Workspace.activeWindow;
        if (row.intent === "prepare"
                && (!shellOwnsFocus(active, Tiling.alive(active) ? active.output : null)
                    || active.appletPopup !== true || String(active.output.name) !== row.outputName)) {
            response.reason = "popup-focus-unconfirmed";
            return response;
        }
        if (row.intent === "prepare") {
            if (fresh) {
                if (targetSerial >= 2147483646) {
                    invalidateTarget("unavailable");
                    response.reason = preparationFailure;
                    return response;
                }
                exchange.nonce = epoch + ":" + (++targetSerial);
                exchange.outputName = row.outputName;
                response.ready = prepareTarget(row.outputName);
            } else {
                response.ready = validateTarget();
            }
            response.token = response.ready ? exchange.nonce : "";
        } else {
            if (row.token === "" || row.token !== exchange.nonce
                    || row.outputName !== exchange.outputName) {
                response.reason = "wrong-preparation";
                return response;
            }
            response.ready = validateTarget();
        }
        response.reason = response.ready ? "" : preparationFailure;
        if (row.intent === "prepare") {
            actor.outcome = response.ready ? "prepared" : response.reason;
        }
        return response;
    }

    function finishRead(): void {
        reading = false;
        if (again) {
            again = false;
            Qt.callLater(probe.scan);
        }
    }

    DBusCall {
        id: ownerLookup
        service: "org.freedesktop.DBus"
        path: "/org/freedesktop/DBus"
        dbusInterface: "org.freedesktop.DBus"
        method: "GetNameOwner"
        arguments: ["org.kde.plasmashell"]
        onFinished: value => {
            probe.readOwner = String(value[0]);
            if (probe.targetProbe) {
                shellIdentityLookup.arguments = [probe.readOwner];
                shellIdentityLookup.call();
            } else {
                probe.readMailboxes();
            }
        }
        onFailed: {
            if (probe.targetProbe) probe.reconcileTargetConsumers(null);
            probe.finishRead();
        }
    }
    DBusCall {
        id: shellIdentityLookup
        service: "org.freedesktop.DBus"
        path: "/org/freedesktop/DBus"
        dbusInterface: "org.freedesktop.DBus"
        method: "GetConnectionUnixProcessID"
        onFinished: value => {
            const pid = Number(value[0]);
            if (!Number.isInteger(pid) || pid <= 0) {
                probe.shellPid = 0;
                probe.shellPidOwner = "";
                probe.targetViewChanged("shell-pid");
                probe.reconcileTargetConsumers(null);
                probe.finishRead();
                return;
            }
            if (probe.shellPidOwner !== "" && probe.shellPidOwner !== probe.readOwner) {
                probe.targetViewChanged("shell-owner");
                probe.targetExchange = null;
            }
            probe.shellPid = pid;
            probe.shellPidOwner = probe.readOwner;
            probe.readMailboxes();
        }
        onFailed: {
            probe.shellPid = 0;
            probe.shellPidOwner = "";
            probe.targetViewChanged("shell-lookup");
            probe.reconcileTargetConsumers(null);
            probe.finishRead();
        }
    }

    function readMailboxes(): void {
        const target = probe.targetProbe;
        reader.arguments = ["var rows=[],widgets=[],complete=true;panels().forEach(function(p) {"
            + "p.widgets('org.plasmafusion.layoutprobe').forEach(function(w) {"
            + (target ? "if(widgets.length>=16){complete=false;return;}"
                + "var item={id:w.id,consumer:null};widgets.push(item);" : "")
            + "w.currentConfigGroup=['General'];try {var text=w.readConfig('layoutRequest','');"
            + (target ? "if(text.length>2048)return;" : "")
            + "var q=JSON.parse(text);"
            + (target ? "if(typeof q.consumer!=='string'||!q.consumer.length||q.consumer.length>128"
                + "||!Number.isInteger(q.request)||q.request<=0||q.request>2147483646)return;"
                + "item.consumer=q.consumer;" : "")
            + "rows.push({id:w.id,consumer:q.consumer,request:q.request,"
            + "version:q.version,intent:q.intent,outputName:q.outputName,token:q.token,"
            + "viewEpoch:q.viewEpoch,viewGeneration:q.viewGeneration,desktopId:q.desktopId,"
            + "activityId:q.activityId,viewOutputName:q.viewOutputName,consumerLease:q.consumerLease});"
            + "}catch(e){} }); });"
            + (target ? "print(JSON.stringify({complete:complete,widgets:widgets,rows:rows}));"
                : "print(JSON.stringify(rows));")];
        reader.call();
    }

    DBusCall {
        id: reader
        service: probe.readOwner
        path: "/PlasmaShell"
        dbusInterface: "org.kde.PlasmaShell"
        method: "evaluateScript"
        onFinished: value => {
            probe.replyOwner = probe.readOwner;
            let data;
            try {
                data = JSON.parse(String(value[0]));
            } catch (error) {
                if (probe.targetProbe) probe.reconcileTargetConsumers(null);
                probe.finishRead();
                console.warn("layout-probe: malformed mailbox snapshot");
                return;
            }
            const rows = probe.targetProbe ? probe.consumeTargetInventory(data) : data;
            if (!Array.isArray(rows)) {
                probe.finishRead();
                console.warn("layout-probe: mailbox inventory unconfirmed");
                return;
            }
            probe.recipients = rows;
            console.info("layout-probe: mailbox rows", probe.recipients.length);
            probe.queuePublication(probe.recipients, probe.replyOwner);
            probe.finishRead();
        }
        onFailed: {
            if (probe.targetProbe) probe.reconcileTargetConsumers(null);
            probe.finishRead();
            console.warn("layout-probe: mailbox read failed");
        }
    }
    DBusCall {
        id: writer
        // Each publication uses its captured unique destination, including delayed replies.
        service: ""
        path: "/PlasmaShell"
        dbusInterface: "org.kde.PlasmaShell"
        method: "evaluateScript"
        onFinished: value => console.info("layout-probe: publication writes", String(value[0]))
        onFailed: console.warn("layout-probe: publication failed")
    }
    ShortcutHandler {
        name: "Plasma Fusion: Layout Probe Wake"
        text: i18n("Wake the isolated layout transport probe")
        sequence: ""
        onActivated: {
            console.info("layout-probe: wake received");
            probe.traceFocus("wake");
            probe.traceView("wake", "wake", probe.targetGeneration, probe.preparedTarget !== null);
            probe.scan();
        }
    }
    Connections {
        target: Workspace
        enabled: probe.authorized && !probe.stopping
        function onWindowActivated(window) {
            if (probe.viewLossProbe && Tiling.eligibleForMaster(window)) {
                probe.viewLossSubject = window;
            }
            if (probe.targetProbe) {
                probe.trackTargetActivation(window);
            } else if (Tiling.eligibleForMaster(window)) {
                probe.lastEligibleWindow = window;
            }
            probe.traceFocus("activation");
        }
        function onWindowRemoved(window) {
            const remembered = window === probe.lastEligibleWindow;
            const focused = window === probe.lastFocusedWindow;
            const handed = probe.targetHandoff && (probe.targetHandoff.source === window
                || probe.targetHandoff.popup === window || probe.targetHandoff.window === window);
            if (focused) {
                probe.lastFocusedWindow = null;
            }
            if (probe.targetProbe && (remembered || (probe.preparedTarget
                    && probe.preparedTarget.window === window))) {
                probe.targetMembershipChanged("window-removed");
            } else if (probe.targetProbe && (focused || handed || (probe.preparedTarget
                    && probe.preparedTarget.focusSurface === window))) {
                probe.advanceTargetContext("focus-changed", "window-removed");
            }
            if (remembered) {
                probe.lastEligibleWindow = null;
                probe.traceFocus("removed");
            }
        }
        function onCurrentDesktopChanged() {
            if (probe.targetProbe) probe.targetViewChanged("current-desktop");
        }
        function onCurrentActivityChanged() {
            if (probe.targetProbe) probe.targetViewChanged("current-activity");
        }
        function onScreensChanged() {
            if (probe.targetProbe) probe.targetViewChanged("screens");
        }
        function onDesktopsChanged() {
            if (probe.targetProbe) probe.targetViewChanged("desktops");
        }
        function onActivitiesChanged() {
            if (probe.targetProbe) probe.targetViewChanged("activities");
        }
    }
    Connections {
        target: probe.lastEligibleWindow
        enabled: probe.authorized && probe.targetProbe && !probe.stopping
        function onDesktopsChanged() { probe.targetMembershipChanged("window-desktops"); }
        function onActivitiesChanged() { probe.targetMembershipChanged("window-activities"); }
        function onOutputChanged() { probe.targetMembershipChanged("window-output"); }
        function onMinimizedChanged() { probe.targetEligibilityChanged("window-minimized"); }
        function onFullScreenChanged() { probe.targetEligibilityChanged("window-fullscreen"); }
        function onMaximizedChanged() { probe.targetEligibilityChanged("window-maximized"); }
        function onTileChanged() { probe.targetEligibilityChanged("window-tile"); }
        function onSkipTaskbarChanged() { probe.targetEligibilityChanged("window-skip-taskbar"); }
        function onSkipSwitcherChanged() { probe.targetEligibilityChanged("window-skip-switcher"); }
        function onTransientChanged() { probe.targetEligibilityChanged("window-transient"); }
        function onModalChanged() { probe.targetEligibilityChanged("window-modal"); }
    }
    Component.onCompleted: {
        authorized = KWin.readConfig("ProbeAuthorized", false) === true;
        if (!authorized) {
            console.warn("layout-probe: authorization marker absent; probe stays inert");
            return;
        }
        dropRetirementFrame = KWin.readConfig("DropRetirementFrame", false) === true;
        focusProbe = KWin.readConfig("FocusProbe", false) === true;
        targetProbe = KWin.readConfig("TargetProbe", false) === true;
        mixedLifetimeProbe = KWin.readConfig("MixedLifetimeProbe", false) === true;
        viewLossProbe = targetProbe && KWin.readConfig("ViewLossProbe", false) === true;
        if (viewLossProbe) {
            viewLossScreens = Workspace.screens.slice();
        }
        if (targetProbe) {
            lastFocusedWindow = Workspace.activeWindow;
            if (Tiling.eligibleForMaster(lastFocusedWindow)) {
                lastEligibleWindow = lastFocusedWindow;
            }
        }
        const delay = Number(KWin.readConfig("ReplyDelayMs", 0));
        replyDelayMs = delay >= 0 && delay <= 3000 && delay % 1 === 0 ? delay : 0;
        if (typeof Workspace.transientTiling === "function") {
            const api = Workspace.transientTiling();
            if (api) {
                const token = String(api.registerProvider(probe));
                // A public lifecycle label, not authentication; never publish the ownership token.
                epoch = Qt.md5(token);
                capable = providerAccepted(token);
                competingProviderRejected = !providerAccepted(String(api.registerProvider(competingProvider)));
                refusal = api.createTile(null, Workspace.currentDesktop, Qt.rect(0, 0, 0, 0)).result;
            }
        }
        console.info("layout-probe: initialized", capable, refusal);
        identityName = "org.plasmafusion.LayoutProbe.p" + epoch;
        // Only an alias on the existing connection: no objects or methods are exported.
        registration = DBus.SessionBus.asyncCall({
            service: "org.freedesktop.DBus", path: "/org/freedesktop/DBus",
            iface: "org.freedesktop.DBus", member: "RequestName", signature: "(su)",
            arguments: [identityName, new DBus.uint32(4)]
        });
    }
    Component.onDestruction: {
        stopping = true;
        cancelPublication();
        if (dropRetirementFrame) {
            console.info("layout-probe: retirement frame deliberately dropped");
        } else {
            probe.publish("offline", probe.recipients, probe.replyOwner);
        }
        if (identityName !== "") {
            identityRelease.arguments = [identityName];
            identityRelease.call();
        }
        if (registration) {
            registration.destroy();
        }
    }
}
