// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid

import "sources"
import "../code/chips.js" as Chips

// Live chips (LiveChips board, docs/parts/shell-livechips.md): at the start of the top bar's right
// cluster, what uses the microphone, the camera or the screen, who controls this computer or has
// signed in over SSH, and what runs on its own (a screen recording, a timed Keep awake). Nothing in
// use: the widget is hidden and the bar is as without it. The privacy capsule opens the panel
// under it on a click, and shows it as an interactive tooltip on hover (its buttons work there
// too); the recording chip's button finishes the recording; the Keep awake chip opens quick
// settings' Keep awake page. The tray items these signals come from are hidden by the layout and
// the setup (TRAY_ITEMS_REPLACED_BY_CHIPS).
PlasmoidItem {
    id: root

    FusionMetrics {
        id: m
        area: Plasmoid.containment ? Plasmoid.containment.availableScreenRect : Qt.rect(0, 0, 1440, 900)
    }

    // ---- the sources (plasma-pa's and kpipewire's QML modules are optional: Loaders)
    Loader {
        id: microphoneSource
        asynchronous: true
        source: "sources/Microphone.qml"
    }
    Loader {
        id: cameraSource
        asynchronous: true
        source: "sources/Camera.qml"
    }
    StatusItems {
        id: statusItems
    }
    RemoteLogins {
        id: remoteLogins
    }
    KeepAwake {
        id: keepAwake
        appletRoot: root
    }

    readonly property var microphoneApps: microphoneSource.item ? microphoneSource.item.apps : []
    readonly property bool cameraInUse: cameraSource.item ? cameraSource.item.inUse : false
    readonly property var screenSessions: statusItems.portal.filter(s => s.kind === "screen")
    readonly property var remoteSessions: statusItems.portal.filter(s => s.kind === "remote")
    readonly property var capsule: Chips.capsule({
        "microphone": microphoneApps.length > 0,
        "camera": cameraInUse,
        "screen": screenSessions.length > 0,
        "remote": remoteSessions.length > 0,
        "ssh": remoteLogins.inUse
    })
    readonly property bool anything: capsule.kinds.length > 0 || statusItems.recording !== null || keepAwake.inUse
    readonly property bool dark: Kirigami.ColorUtils.brightnessForColor(Kirigami.Theme.backgroundColor) === Kirigami.ColorUtils.Dark

    // What the chips show, for the session tests (journal: "livechips: state ...").
    readonly property string summary: JSON.stringify({
        capsule: capsule.kinds,
        tint: capsule.tintKind,
        recording: statusItems.recording ? statusItems.recording.time : null,
        keepAwake: keepAwake.inUse ? keepAwake.remaining.total : 0
    })
    onSummaryChanged: {
        console.info("livechips: state " + summary);
        chipsReport.restart();
    }
    // Test hook: the chips' places once the panel has laid the widget out again.
    Timer {
        id: chipsReport
        interval: 400
        onTriggered: {
            const row = root.compactRepresentationItem ? root.compactRepresentationItem.chipRow : null;
            if (row) {
                console.info("livechips: chips at " + row.report());
            }
        }
    }
    // The panel closes when nothing is left in it.
    onCapsuleChanged: if (capsule.kinds.length === 0 && expanded) expanded = false

    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    Plasmoid.status: expanded ? PlasmaCore.Types.RequiresAttentionStatus
                              : anything ? PlasmaCore.Types.ActiveStatus : PlasmaCore.Types.HiddenStatus
    Plasmoid.icon: "security-medium"
    preferredRepresentation: compactRepresentation
    activationTogglesExpanded: false
    toolTipMainText: ""
    toolTipSubText: ""

    Connections {
        target: Plasmoid
        function onActivated() {
            if (root.capsule.kinds.length > 0) {
                root.expanded = !root.expanded;
            }
        }
    }

    compactRepresentation: Item {
        readonly property alias chipRow: chips
        Layout.minimumWidth: root.anything ? chips.implicitWidth : 0
        Layout.preferredWidth: root.anything ? chips.implicitWidth : 0
        Layout.maximumWidth: root.anything ? chips.implicitWidth : 0
        Layout.preferredHeight: chips.implicitHeight

        ChipRow {
            id: chips
            anchors.centerIn: parent
            metrics: m
            dark: root.dark
            capsule: root.capsule
            recording: statusItems.recording
            keepAwakeOn: keepAwake.inUse
            keepAwakeLeft: keepAwake.remaining
            panelOpen: root.expanded
            onCapsuleClicked: root.expanded = !root.expanded
            onStopRecording: statusItems.stopRecording()
            onKeepAwakeClicked: keepAwake.open()
        }
        // On hover the panel shows as the capsule's tooltip (the board's "click or hover"), not
        // while the pop-up is open.
        PlasmaCore.ToolTipArea {
            x: chips.x + chips.capsuleItem.x
            y: chips.y + chips.capsuleItem.y
            width: chips.capsuleItem.width
            height: chips.capsuleItem.height
            visible: chips.capsuleItem.visible
            active: !root.expanded
            interactive: true
            location: Plasmoid.location
            mainItem: InUsePanel {
                hover: true
                metrics: m
                dark: root.dark
                microphoneApps: root.microphoneApps
                cameraApps: cameraSource.item ? cameraSource.item.apps : []
                cameraNames: cameraSource.item ? cameraSource.item.cameras : []
                cameraInUse: root.cameraInUse
                portalSessions: statusItems.portal
                logins: remoteLogins.sessions
                onEndSession: key => statusItems.endSession(key)
            }
        }
    }

    fullRepresentation: InUsePanel {
        metrics: m
        dark: root.dark
        microphoneApps: root.microphoneApps
        cameraApps: cameraSource.item ? cameraSource.item.apps : []
        cameraNames: cameraSource.item ? cameraSource.item.cameras : []
        cameraInUse: root.cameraInUse
        portalSessions: statusItems.portal
        logins: remoteLogins.sessions
        onEndSession: key => statusItems.endSession(key)
        onCloseRequested: root.expanded = false
    }
}
