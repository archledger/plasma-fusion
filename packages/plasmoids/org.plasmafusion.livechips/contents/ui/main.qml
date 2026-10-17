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
// the setup (TRAY_ITEMS_REPLACED_BY_CHIPS). While the top bar of this screen is hidden (the settings
// page's "Hide the top bar automatically"), the island at the top centre of the screen shows them
// instead, and the music playing (Island.qml, board Island.dc.html).
PlasmoidItem {
    id: root

    // Debug output for tests: QT_LOGGING_RULES="org.plasmafusion.livechips.debug=true".
    LoggingCategory {
        id: log
        name: "org.plasmafusion.livechips"
        defaultLogLevel: LoggingCategory.Warning
    }

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
    // The island's own sources, only while the bar is hidden (nothing runs for them with the
    // switch off): the music playing (the MPRIS module is optional) and whether the screen's
    // active window is full screen.
    Loader {
        id: mediaSource
        active: Plasmoid.configuration.barHidden
        asynchronous: true
        source: "sources/Media.qml"
    }
    // Plasma's own notices (the volume, the brightness and the rest), which the island shows while
    // the tablet KWin script hides Plasma's pop-up on this screen.
    Loader {
        id: osdSource
        active: Plasmoid.configuration.barHidden
        source: "sources/Osd.qml"
    }
    Loader {
        id: fullScreenSource
        active: Plasmoid.configuration.barHidden
        sourceComponent: FullScreen {
            screenGeometry: root.screenGeometry
        }
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
    readonly property rect screenGeometry: Plasmoid.containment ? Plasmoid.containment.screenGeometry : Qt.rect(0, 0, 0, 0)

    // ---- the island (board Island.dc.html)
    readonly property var media: mediaSource.item
    readonly property var islandContent: Chips.island({
        "privacy": capsule.kinds,
        "recording": statusItems.recording !== null,
        "keepAwake": keepAwake.inUse,
        "music": media !== null && media.playing,
        "musicOpened": island.opened === "music",
        "musicPlayer": media !== null && !!media.player,
        "fullScreen": fullScreenSource.item ? fullScreenSource.item.active : false,
        // An island opened by a click stays as it is (a notice would close it).
        "notice": osdSource.item && island.opened === "" ? osdSource.item.notice : null
    })
    readonly property var islandRows: Chips.islandRows(microphoneApps.map(a => ({ name: a.name, muted: a.muted })),
                                                       cameraSource.item ? cameraSource.item.apps : [], cameraInUse,
                                                       cameraSource.item ? cameraSource.item.cameras : [], statusItems.portal, remoteLogins.sessions)
    Island {
        id: island
        metrics: m
        dark: root.dark
        barHidden: Plasmoid.configuration.barHidden
        screenGeometry: root.screenGeometry
        content: root.islandContent
        rows: root.islandRows
        recording: statusItems.recording
        keepAwakeLeft: keepAwake.inUse ? keepAwake.remaining : null
        media: root.media
        onStopRecording: statusItems.stopRecording()
        onOpenKeepAwake: keepAwake.open()
        onRowAction: row => {
            if (row.action === "mute" || row.action === "unmute") {
                // the app's streams together: Mute while any of them records, Unmute them all
                for (const i of row.microphones) {
                    if (i >= 0 && i < root.microphoneApps.length && root.microphoneApps[i].muted !== (row.action === "mute")) {
                        root.microphoneApps[i].setMuted(row.action === "mute");
                    }
                }
            } else if (row.action === "stop" || row.action === "end") {
                statusItems.endSession(row.session);
            }
        }
    }
    // The tablet KWin script made Plasma's pop-up on this screen transparent: show its notice.
    Connections {
        target: Plasmoid.configuration
        function onNoticeRequestChanged() {
            if (osdSource.item && String(Plasmoid.configuration.noticeRequest) !== "") {
                osdSource.item.request();
            }
        }
    }

    // Test hook: [General] islandRequest "open:NONCE" or "close:NONCE" opens or closes the island.
    Connections {
        target: Plasmoid.configuration
        function onIslandRequestChanged() {
            const request = String(Plasmoid.configuration.islandRequest);
            console.debug(log, "livechips: islandRequest " + request);
            if (request.startsWith("open:")) {
                island.open(island.items[0] || "");
            } else if (request.startsWith("close:")) {
                island.close();
            }
        }
    }

    // What the chips show, for the session tests ("livechips: state ...", debug output).
    readonly property string summary: JSON.stringify({
        capsule: capsule.kinds,
        tint: capsule.tintKind,
        recording: statusItems.recording ? statusItems.recording.time : null,
        keepAwake: keepAwake.inUse ? keepAwake.remaining.total : 0
    })
    onSummaryChanged: console.debug(log, "livechips: state " + summary)
    // Test hook: the chips' places once the panel has laid the widget out again, when a chip comes
    // or goes (not when only the recording's time or Keep awake's moves on).
    readonly property string layoutKey: Chips.layoutKey(capsule.kinds, statusItems.recording, keepAwake.inUse)
    onLayoutKeyChanged: chipsReport.restart()
    Timer {
        id: chipsReport
        interval: 400
        onTriggered: {
            const row = root.compactRepresentationItem ? root.compactRepresentationItem.chipRow : null;
            if (row) {
                console.debug(log, "livechips: chips at " + row.report());
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
