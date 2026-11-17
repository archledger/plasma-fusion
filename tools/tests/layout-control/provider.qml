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
                    ready: preparation.ready, reason: preparation.reason,
                    targetClass: Tiling.alive(window) ? String(window.resourceClass) : "",
                    targetAlive: Tiling.alive(window)
                }));
            }
            return {id: row.id, packet: JSON.stringify({
                consumer: row.consumer, epoch: epoch, revision: ++revision,
                status: status, capable: capable, refusal: refusal,
                request: row.request,
                preparation: preparation,
                targetContext: status === "online" && probe.targetProbe
                    ? probe.captureTargetContext(row.outputName) : null,
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
            advanceTargetContext("focus-changed");
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

    function targetViewChanged(): void {
        lastEligibleWindow = null;
        advanceTargetContext("view-changed");
    }

    function targetMembershipChanged(): void {
        lastEligibleWindow = null;
        advanceTargetContext("target-departed");
    }

    function targetEligibilityChanged(): void {
        if (!Tiling.eligibleForMaster(lastEligibleWindow)) {
            targetMembershipChanged();
        }
    }

    function advanceTargetContext(reason: string): void {
        targetHandoff = null;
        if (targetGeneration >= 0) {
            targetGeneration = targetGeneration < 2147483646 ? targetGeneration + 1 : -1;
        }
        invalidateTarget(reason);
        if (probe.targetProbe && !probe.stopping) {
            probe.traceFocus("context-changed");
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
        if (targetExchange && targetExchange.owner !== readOwner) {
            targetExchange = null;
            lastEligibleWindow = null;
            invalidateTarget("shell-replaced");
        }
        let exchange = targetExchange;
        if (exchange && (exchange.consumer !== row.consumer || exchange.id !== row.id)) {
            response.reason = "busy";
            return response;
        }
        const payload = JSON.stringify([row.intent, row.outputName, row.token, row.viewEpoch,
                                        row.viewGeneration, row.desktopId, row.activityId,
                                        row.viewOutputName]);
        if (exchange && (row.request < exchange.request
                || (row.request === exchange.request && payload !== exchange.payload))) {
            response.reason = "stale-or-conflicting-request";
            return response;
        }
        const fresh = !exchange || row.request > exchange.request;
        if (!exchange) {
            exchange = {owner: readOwner, consumer: row.consumer, id: row.id,
                        request: 0, payload: "", outputName: "", nonce: ""};
            targetExchange = exchange;
        }
        if (fresh) {
            exchange.request = row.request;
            exchange.payload = payload;
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
        onFailed: probe.finishRead()
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
                probe.targetViewChanged();
                probe.finishRead();
                return;
            }
            if (probe.shellPidOwner !== "" && probe.shellPidOwner !== probe.readOwner) {
                probe.targetViewChanged();
                probe.targetExchange = null;
            }
            probe.shellPid = pid;
            probe.shellPidOwner = probe.readOwner;
            probe.readMailboxes();
        }
        onFailed: {
            probe.shellPid = 0;
            probe.shellPidOwner = "";
            probe.targetViewChanged();
            probe.finishRead();
        }
    }

    function readMailboxes(): void {
        const bounded = probe.targetProbe ? "if(rows.length>=16)return;" : "";
        reader.arguments = ["var rows=[];panels().forEach(function(p) {"
            + "p.widgets('org.plasmafusion.layoutprobe').forEach(function(w) {"
            + bounded
            + "w.currentConfigGroup=['General'];try {var text=w.readConfig('layoutRequest','');"
            + (probe.targetProbe ? "if(text.length>2048)return;" : "")
            + "var q=JSON.parse(text);rows.push({id:w.id,consumer:q.consumer,request:q.request,"
            + "version:q.version,intent:q.intent,outputName:q.outputName,token:q.token,"
            + "viewEpoch:q.viewEpoch,viewGeneration:q.viewGeneration,desktopId:q.desktopId,"
            + "activityId:q.activityId,viewOutputName:q.viewOutputName});"
            + "}catch(e){} }); });"
            + "print(JSON.stringify(rows));"];
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
            probe.recipients = JSON.parse(String(value[0]));
            console.info("layout-probe: mailbox rows", probe.recipients.length);
            probe.queuePublication(probe.recipients, probe.replyOwner);
            probe.finishRead();
        }
        onFailed: {
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
            probe.scan();
        }
    }
    Connections {
        target: Workspace
        enabled: probe.authorized && !probe.stopping
        function onWindowActivated(window) {
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
                probe.targetMembershipChanged();
            } else if (probe.targetProbe && (focused || handed || (probe.preparedTarget
                    && probe.preparedTarget.focusSurface === window))) {
                probe.advanceTargetContext("focus-changed");
            }
            if (remembered) {
                probe.lastEligibleWindow = null;
                probe.traceFocus("removed");
            }
        }
        function onCurrentDesktopChanged() {
            if (probe.targetProbe) probe.targetViewChanged();
        }
        function onCurrentActivityChanged() {
            if (probe.targetProbe) probe.targetViewChanged();
        }
        function onScreensChanged() {
            if (probe.targetProbe) probe.targetViewChanged();
        }
        function onDesktopsChanged() {
            if (probe.targetProbe) probe.targetViewChanged();
        }
        function onActivitiesChanged() {
            if (probe.targetProbe) probe.targetViewChanged();
        }
    }
    Connections {
        target: probe.lastEligibleWindow
        enabled: probe.authorized && probe.targetProbe && !probe.stopping
        function onDesktopsChanged() { probe.targetMembershipChanged(); }
        function onActivitiesChanged() { probe.targetMembershipChanged(); }
        function onOutputChanged() { probe.targetMembershipChanged(); }
        function onMinimizedChanged() { probe.targetEligibilityChanged(); }
        function onFullScreenChanged() { probe.targetEligibilityChanged(); }
        function onMaximizedChanged() { probe.targetEligibilityChanged(); }
        function onTileChanged() { probe.targetEligibilityChanged(); }
        function onSkipTaskbarChanged() { probe.targetEligibilityChanged(); }
        function onSkipSwitcherChanged() { probe.targetEligibilityChanged(); }
        function onTransientChanged() { probe.targetEligibilityChanged(); }
        function onModalChanged() { probe.targetEligibilityChanged(); }
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
