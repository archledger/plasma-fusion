/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import QtQuick.Window
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.workspace.dbus as DBus

PlasmoidItem {
    id: probe
    implicitWidth: targetEnabled ? 280 : focusEnabled ? 120 : 24
    implicitHeight: 24
    Layout.minimumWidth: implicitWidth
    Layout.preferredWidth: implicitWidth
    readonly property bool focusEnabled: Plasmoid.configuration.focusProbe === true
    readonly property bool targetEnabled: Plasmoid.configuration.targetProbe === true
    property bool focusPopupOpen: false
    property string queryIntent: "query"
    property string requestOutput: ""
    property string preparedToken: ""
    property var targetContext: null
    property var requestContext: null
    property var preparedContext: null
    property bool preparedReady: false
    property var pendingMenuContext: null
    property bool targetPreparationPending: false
    // Probe-only correlation, not a production identity or authentication mechanism.
    readonly property string boot: Date.now() + ":" + Math.random()
    property string phase: "unknown"
    property string epoch: ""
    property int revision: -1
    property int accepted: 0
    property int requestNumber: 1
    property string boundEpoch: ""
    property string boundOwner: ""
    property string boundIdentity: ""
    property bool stopped: false
    property bool verifying: false
    property var checkingPacket: null
    property var pendingPacket: null
    property var queryDeadline: null
    readonly property int queryTimeoutMs: {
        const value = Number(Plasmoid.configuration.queryTimeoutMs);
        return value >= 100 && value <= 10000 && value % 1 === 0 ? value : 10000;
    }

    Component {
        id: deadlineFactory
        Timer {
            id: deadline
            required property var receiver
            required property int generation
            repeat: false
            triggeredOnStart: false
            onTriggered: {
                if (deadline.receiver && deadline.receiver.queryDeadline === deadline) {
                    deadline.receiver.queryDeadline = null;
                    deadline.receiver.queryTimedOut(deadline.generation);
                }
                deadline.destroy();
            }
        }
    }

    function stopQueryDeadline(): void {
        if (queryDeadline) {
            const timer = queryDeadline;
            queryDeadline = null;
            timer.stop();
            timer.destroy();
        }
    }

    function queryTimedOut(generation: int): void {
        if (probe.stopped || generation !== probe.requestNumber || probe.boundEpoch !== "") {
            return;
        }
        // Uncertainty does not cancel the outstanding query or authorize a retry.
        probe.phase = "unconfirmed";
        probe.observe(null);
    }

    function finishVerification(): void {
        verifying = false;
        checkingPacket = null;
        if (pendingPacket) {
            Qt.callLater(verifyPending);
        }
    }

    function verifyPending(): void {
        if (stopped || verifying || !pendingPacket) {
            return;
        }
        const packet = pendingPacket;
        pendingPacket = null;
        verifying = true;
        checkingPacket = packet;
        DBus.SessionBus.asyncCall({
            service: "org.freedesktop.DBus", path: "/org/freedesktop/DBus",
            iface: "org.freedesktop.DBus", member: "GetNameOwner", arguments: ["org.kde.KWin"]
        }, reply => {
            if (String(reply.value) !== packet.backendOwner) {
                console.info("layout-probe-rejected backend owner ", probe.boot);
                probe.finishVerification();
                return;
            }
            if (packet.status === "offline") {
                if (packet.backendOwner === probe.boundOwner
                        && packet.identityName === probe.boundIdentity) {
                    probe.acceptPacket(packet);
                }
                probe.finishVerification();
                return;
            }
            DBus.SessionBus.asyncCall({
                service: "org.freedesktop.DBus", path: "/org/freedesktop/DBus",
                iface: "org.freedesktop.DBus", member: "GetNameOwner", arguments: [packet.identityName]
            }, identity => {
                if (String(identity.value) === packet.backendOwner) {
                    probe.acceptPacket(packet);
                }
                probe.finishVerification();
            }, () => probe.finishVerification());
        }, () => probe.finishVerification());
    }

    function acceptPacket(packet: var): void {
        // Recheck after asynchronous lookups: retirement may have advanced the query meanwhile.
        if (stopped || packet.request !== requestNumber) {
            return;
        }
        if (boundEpoch !== "" && packet.epoch !== boundEpoch) {
            freshQuery(true);
            return;
        }
        if (packet.revision <= revision) {
            return;
        }
        boundEpoch = packet.epoch;
        boundOwner = packet.backendOwner;
        boundIdentity = packet.identityName;
        stopQueryDeadline();
        phase = packet.status === "online" && !packet.capable ? "unsupported" : packet.status;
        epoch = packet.epoch;
        revision = packet.revision;
        ++accepted;
        if (probe.targetEnabled) {
            const context = packet.targetContext;
            probe.targetContext = context && context.epoch === packet.epoch
                && Number.isInteger(context.generation) && context.generation >= 0
                && context.generation <= 2147483646
                && typeof context.desktopId === "string" && context.desktopId.length > 0
                && context.desktopId.length <= 128 && typeof context.activityId === "string"
                && context.activityId.length > 0 && context.activityId.length <= 128
                && typeof context.outputName === "string" && context.outputName.length > 0
                && context.outputName.length <= 128 && typeof context.consumerLease === "string"
                && context.consumerLease.length > 0 && context.consumerLease.length <= 128 ? {
                    epoch: context.epoch, generation: context.generation,
                    desktopId: context.desktopId, activityId: context.activityId,
                    outputName: context.outputName, consumerLease: context.consumerLease
                } : null;
        }
        if (probe.targetEnabled && packet.preparation && packet.preparation.intent === "prepare") {
            const ready = packet.preparation.ready === true && probe.targetContext
                && typeof packet.preparation.token === "string"
                && packet.preparation.token.length > 0 && packet.preparation.token.length <= 128;
            probe.preparedReady = !!ready;
            if (ready) {
                probe.preparedToken = packet.preparation.token;
                probe.preparedContext = {
                    epoch: probe.targetContext.epoch, generation: probe.targetContext.generation,
                    desktopId: probe.targetContext.desktopId, activityId: probe.targetContext.activityId,
                    outputName: probe.targetContext.outputName,
                    consumerLease: probe.targetContext.consumerLease
                };
            }
        } else if (probe.targetEnabled && packet.preparation) {
            probe.preparedReady = packet.preparation.intent === "validate"
                && packet.preparation.ready === true && !!probe.targetContext
                && !!probe.preparedContext
                && probe.targetContext.consumerLease === probe.preparedContext.consumerLease;
        }
        observe(packet);
        if (packet.status === "offline") {
            freshQuery(true);
        }
    }

    function sendQuery(): void {
        if (stopped) {
            return;
        }
        stopQueryDeadline();
        queryDeadline = deadlineFactory.createObject(probe, {
            receiver: probe, generation: requestNumber, interval: queryTimeoutMs
        });
        if (!queryDeadline) {
            stopped = true;
            phase = "unknown";
            observe(null);
            console.warn("layout-probe: cannot create private query deadline");
            return;
        }
        queryDeadline.start();
        console.info("layout-probe-query", JSON.stringify({
            boot: boot, request: requestNumber, deadlineMs: queryDeadline.interval
        }));
        const request = {consumer: boot, request: requestNumber};
        if (probe.targetEnabled) {
            if (probe.queryIntent === "query") {
                probe.requestOutput = Screen.name;
            }
            const context = probe.queryIntent === "validate"
                ? probe.preparedContext : probe.requestContext;
            Object.assign(request, {
                version: 1, intent: probe.queryIntent, outputName: probe.requestOutput,
                token: probe.queryIntent === "validate" ? probe.preparedToken : "",
                viewEpoch: context ? context.epoch : "",
                viewGeneration: context ? context.generation : -1,
                desktopId: context ? context.desktopId : "",
                activityId: context ? context.activityId : "",
                viewOutputName: context ? context.outputName : "",
                consumerLease: context ? context.consumerLease : ""
            });
        }
        Plasmoid.configuration.layoutRequest = JSON.stringify(request);
        // Desktop scripting reads the saved group, not this unsaved property map.
        Plasmoid.configuration.writeConfig();
        DBus.SessionBus.asyncCall({
            service: "org.kde.kglobalaccel", path: "/component/kwin",
            iface: "org.kde.kglobalaccel.Component", member: "invokeShortcut",
            arguments: ["Plasma Fusion: Layout Probe Wake"]
        }, () => console.info("layout-probe: wake dispatched"),
           error => console.warn("layout-probe: wake failed", error.name));
    }

    function freshQuery(showUnknown: bool): void {
        probe.queryIntent = "query";
        if (probe.targetEnabled) {
            probe.preparedReady = false;
        }
        stopQueryDeadline();
        if (requestNumber >= 2147483646) {
            stopped = true;
            phase = "unknown";
            observe(null);
            return;
        }
        const requested = ++requestNumber;
        boundEpoch = "";
        boundOwner = "";
        boundIdentity = "";
        pendingPacket = null;
        revision = -1;
        if (showUnknown) {
            epoch = "";
            phase = "unknown";
            observe(null);
        }
        // Leave the configuration-change stack before publishing another query.
        Qt.callLater(() => {
            if (!probe.stopped && probe.requestNumber === requested) {
                probe.sendQuery();
            }
        });
    }

    function requestTarget(intent: string): void {
        if (!probe.targetEnabled || (intent !== "prepare" && intent !== "validate")) {
            return;
        }
        const context = intent === "prepare" && probe.targetPreparationPending
            ? probe.pendingMenuContext : probe.targetContext;
        const captured = intent === "prepare" && context ? {
            epoch: context.epoch, generation: context.generation, desktopId: context.desktopId,
            activityId: context.activityId, outputName: context.outputName,
            consumerLease: context.consumerLease
        } : null;
        probe.freshQuery(true);
        // freshQuery resets lifecycle requests to query; its captured-generation send is deferred.
        probe.queryIntent = intent;
        probe.requestOutput = Screen.name;
        if (intent === "prepare") {
            probe.preparedToken = "";
            probe.preparedContext = null;
            probe.preparedReady = false;
            probe.requestContext = captured;
            probe.targetPreparationPending = false;
            probe.pendingMenuContext = null;
        }
    }

    function openTargetMenu(): void {
        if (!probe.targetEnabled) {
            return;
        }
        const context = probe.targetContext;
        probe.pendingMenuContext = context ? {
            epoch: context.epoch, generation: context.generation, desktopId: context.desktopId,
            activityId: context.activityId, outputName: context.outputName,
            consumerLease: context.consumerLease
        } : null;
        probe.targetPreparationPending = true;
        probe.focusPopupOpen = true;
    }

    function observe(packet: var): void {
        console.info("layout-probe-observation", JSON.stringify({
            boot: boot, phase: phase, epoch: epoch, revision: revision,
            accepted: accepted, packet: packet, request: requestNumber
        }));
        if (focusEnabled && phase === "online") {
            Qt.callLater(logFocusControl);
        }
    }

    function logFocusControl(): void {
        if (!focusEnabled || focusButton.width <= 0 || focusButton.height <= 0) {
            return;
        }
        const point = focusButton.mapToGlobal(focusButton.width / 2, focusButton.height / 2);
        const validation = validateButton.mapToGlobal(validateButton.width / 2,
                                                     validateButton.height / 2);
        console.info("layout-probe-focus-control", JSON.stringify({
            boot: boot, x: point.x, y: point.y, screen: Screen.name,
            validateX: validation.x, validateY: validation.y
        }));
        if (probe.targetEnabled && probe.queryIntent === "query" && Screen.name !== ""
                && probe.requestOutput !== Screen.name) {
            // One event-driven refresh when attachment/movement changes the bar's output.
            probe.freshQuery(true);
        }
    }
    Controls.Button {
        id: focusButton
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: probe.targetEnabled ? parent.width / 2 : parent.width
        visible: probe.focusEnabled
        enabled: visible
        text: "Focus probe"
        Accessible.name: "Open isolated focus probe"
        onClicked: {
            if (probe.targetEnabled) {
                probe.openTargetMenu();
            } else {
                probe.focusPopupOpen = true;
            }
        }
    }
    Controls.Button {
        id: validateButton
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: parent.width / 2
        visible: probe.targetEnabled
        enabled: visible
        text: i18n("Validate captured")
        Accessible.name: i18n("Validate the captured isolated target without preparing again")
        onClicked: probe.requestTarget("validate")
    }
    PlasmaCore.AppletPopup {
        id: focusPopup
        visualParent: focusButton
        popupDirection: Qt.BottomEdge
        margin: 8
        floating: false
        removeBorderStrategy: PlasmaCore.AppletPopup.Never
        hideOnWindowDeactivate: true
        visible: probe.focusEnabled && probe.focusPopupOpen
        onVisibleChanged: {
            if (visible) {
                focusPopup.requestActivate();
                focusQuery.forceActiveFocus();
            } else {
                probe.targetPreparationPending = false;
                probe.pendingMenuContext = null;
                probe.focusPopupOpen = false;
            }
        }
        mainItem: Controls.Button {
            id: focusQuery
            implicitWidth: 180
            implicitHeight: 60
            focus: true
            text: !probe.targetEnabled ? "Query focus"
                : probe.targetPreparationPending ? i18n("Prepare target") : i18n("Validate target")
            Accessible.name: "Query isolated focus by keyboard"
            onActiveFocusChanged: {
                if (activeFocus && probe.focusEnabled) {
                    console.info("layout-probe-popup-focus", JSON.stringify({
                        boot: probe.boot, screen: Screen.name
                    }));
                }
            }
            Keys.onPressed: event => {
                if ([Qt.Key_Space, Qt.Key_Return, Qt.Key_Enter].includes(event.key)) {
                    event.accepted = true;
                    if (!event.isAutoRepeat) {
                        const intent = probe.targetEnabled && probe.targetPreparationPending
                            ? "prepare" : probe.targetEnabled ? "validate" : "query";
                        console.info("layout-probe-keyboard-query", JSON.stringify({
                            boot: probe.boot, key: event.key, activeFocus: focusQuery.activeFocus,
                            screen: Screen.name, request: probe.requestNumber + 1, intent: intent
                        }));
                        if (probe.targetEnabled) {
                            // A received popup input, not Window.active's transient chain, admits
                            // the one initial native app/panel-to-popup handoff.
                            probe.requestTarget(intent);
                        } else {
                            probe.freshQuery(true);
                        }
                    }
                } else if (event.key === Qt.Key_Escape) {
                    event.accepted = true;
                    probe.focusPopupOpen = false;
                }
            }
        }
    }
    DBus.SignalWatcher {
        enabled: !probe.stopped
        busType: DBus.BusType.Session
        service: "org.freedesktop.DBus"
        path: "/org/freedesktop/DBus"
        iface: "org.freedesktop.DBus"
        function dbusNameOwnerChanged(name, previous, current) {
            // The workspace decoder wraps QString arguments too, not only numeric values.
            name = String(name);
            previous = String(previous);
            current = String(current);
            if (probe.stopped || previous === "" || previous === current) {
                return;
            }
            const bound = previous === probe.boundOwner
                && (name === probe.boundIdentity || name === "org.kde.KWin");
            const packet = probe.checkingPacket;
            const checking = packet && packet.request === probe.requestNumber
                && previous === packet.backendOwner
                && (name === packet.identityName || name === "org.kde.KWin");
            if (bound || checking) {
                console.info("layout-probe-invalidated",
                             JSON.stringify({boot: probe.boot, name: name}));
                probe.freshQuery(true);
            }
        }
        // These signals concern our own bus connection, not the watched provider lifetime.
        function dbusNameAcquired(name) {
        }
        function dbusNameLost(name) {
        }
        function dbusActivatableServicesChanged() {
        }
    }
    Connections {
        target: Plasmoid.configuration
        function onLayoutResponseChanged() {
            let packet;
            try {
                packet = JSON.parse(Plasmoid.configuration.layoutResponse);
            } catch (error) {
                return;
            }
            // Attach the emitter last: packet fields cannot impersonate the receiver lifetime.
            const received = Object.assign({}, packet, {receiverBoot: probe.boot});
            console.info("layout-probe-received", JSON.stringify(received));
            if (probe.stopped || !packet || packet.consumer !== probe.boot
                    || packet.request !== probe.requestNumber
                    || typeof packet.epoch !== "string"
                    || !/^:[0-9]+\.[0-9]+$/.test(packet.backendOwner)
                    || packet.identityName !== "org.plasmafusion.LayoutProbe.p" + packet.epoch
                    || typeof packet.capable !== "boolean"
                    || !["online", "offline"].includes(packet.status)
                    || typeof packet.revision !== "number" || packet.revision % 1 !== 0
                    || packet.revision < 1 || packet.revision > 2147483646) {
                if (packet && packet.consumer === probe.boot
                        && packet.request !== probe.requestNumber) {
                    console.info("layout-probe-rejected request ", JSON.stringify({
                        boot: probe.boot, request: packet.request, current: probe.requestNumber
                    }));
                }
                return;
            }
            // Delivery order is not revision order while the one verifier is busy.
            const queued = probe.pendingPacket;
            if (queued && queued.consumer === packet.consumer && queued.request === packet.request
                    && queued.epoch === packet.epoch && queued.backendOwner === packet.backendOwner
                    && queued.identityName === packet.identityName
                    && queued.revision >= packet.revision) {
                return;
            }
            probe.pendingPacket = packet;
            probe.verifyPending();
        }
    }
    Component.onCompleted: {
        observe(null);
        sendQuery();
    }
    Component.onDestruction: {
        stopped = true;
        stopQueryDeadline();
    }
}
