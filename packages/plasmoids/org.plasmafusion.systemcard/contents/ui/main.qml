/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.workspace.dbus as DBus
import org.kde.ksysguard.sensors as Sensors
import org.kde.kirigami as Kirigami
import org.kde.kwindowsystem
import org.kde.taskmanager as TaskManager

// CPU and memory card of the Main board's desktop widgets: two labelled 5 px bars, CPU in teal
// (#3cc4b0) with its load in percent, memory in blue (#5b9dff) as "used / total GB". Values from
// ksystemstats through org.kde.ksysguard.sensors, as the stock system monitor widget reads them.
//
// Every change on the card redraws the whole desktop window (wallpaper and blurred cards), so the
// card changes as little as it can (docs/parts/desktop-cards.md, "CARD-1"):
// - one update per interval (3 s by default; x 2 in power saver, x 4 on critical battery);
// - a bar steps to its new value (one frame) and glides only for a change of 10 points or more;
// - the sensors are off while nobody can see the card: a maximized or full-screen window on the
//   current virtual desktop of its screen, the card not shown, or the session locked.
//
// The card is the first to give way (ADAPTIVE 5.9, GAPS D5): in portrait, and wherever it would
// reach into the dock's area (104 px; 112 in tablet posture, TABLET 4.14), it draws nothing (no
// frame, no content) and reads no sensors.
PlasmoidItem {
    id: root

    Plasmoid.backgroundHints: hiddenByLayout ? PlasmaCore.Types.NoBackground : PlasmaCore.Types.StandardBackground
    preferredRepresentation: fullRepresentation
    FusionTablet {
        id: tabletState
    }
    // Text scale and pixel grid of the card (docs/parts/desktop-cards.md, "Text scale").
    FusionMetrics {
        id: m
        area: Plasmoid.containment ? Plasmoid.containment.availableScreenRect : Qt.rect(0, 0, 1440, 900)
        tablet: tabletState.tablet
    }

    // --- Room on the desktop ---
    // The card's lower edge in the desktop window (the content's, plus the style's 14 px frame),
    // set by the card; the room ends 16 px above the dock's area.
    property real cardBottom: 0
    readonly property int dockArea: tabletState.tablet ? 112 : 104
    readonly property rect room: Plasmoid.containment ? Plasmoid.containment.availableScreenRect : Qt.rect(0, 0, 0, 0)
    readonly property bool overBudget: cardBottom > 0 && room.height > 0 && cardBottom > room.y + room.height - dockArea - 16 + 1
    readonly property bool hiddenByLayout: m.portrait || overBudget
    onHiddenByLayoutChanged: console.info("systemcard: " + (hiddenByLayout ? "hidden" : "shown") + " (portrait " + m.portrait
                                          + ", bottom " + Math.round(cardBottom) + ", room to "
                                          + Math.round(room.y + room.height - dockArea - 16) + ")")
    // Board card 192 x 92 minus the style's 14 px frame margins (the desktop's 16 px grid makes
    // the card 192 x 96), scaled with the text (the layout script sizes the card the same way).
    // Always the card itself: switchWidth/switchHeight would show the icon whenever the card is
    // not larger than them (libplasma appletShouldBeExpanded).
    readonly property int boardWidth: 164
    readonly property int boardHeight: 64
    readonly property real contentWidth: m.px(boardWidth)
    readonly property real contentHeight: m.px(boardHeight)

    // The user's interval (1-10 s) times the power tier's factor. The power service writes only
    // the hidden powerTier key (0 full, 1 saver, 2 critical), never the user's updateInterval.
    readonly property int powerTier: Math.max(0, Math.min(2, Plasmoid.configuration.powerTier))
    readonly property int updateInterval: Math.max(1000, Plasmoid.configuration.updateInterval) * (1 << powerTier)

    // Debug output for tests: QT_LOGGING_RULES="org.plasmafusion.systemcard.debug=true".
    LoggingCategory {
        id: log
        name: "org.plasmafusion.systemcard"
        defaultLogLevel: LoggingCategory.Warning
    }

    // --- When the card can be seen ---

    // Set by the card (fullRepresentation): it is shown in a visible window.
    property bool cardShown: false

    // Windows on the card's screen and on that screen's current virtual desktop and activity,
    // as the stock panel's touchingWindow model (plasma-desktop Panel.qml) filters them. Any of
    // them maximized or full screen covers the whole card.
    TaskManager.ActivityInfo {
        id: activityInfo
    }
    TaskManager.TasksModel {
        id: screenWindows
        filterByCurrentVirtualDesktop: true
        filterByActivity: true
        filterByScreen: true
        filterMinimized: true
        filterHidden: true
        groupMode: TaskManager.TasksModel.GroupDisabled
        sortMode: TaskManager.TasksModel.SortDisabled
        screenGeometry: Plasmoid.containment ? Plasmoid.containment.screenGeometry : Qt.rect(0, 0, 0, 0)
        activity: activityInfo.currentActivity
    }
    component WindowState: QtObject {
        required property var model
        readonly property bool covers: model.IsMaximized === true || model.IsFullScreen === true
        onCoversChanged: Qt.callLater(root.countCovering)
    }
    Instantiator {
        id: windowStates
        model: screenWindows
        delegate: WindowState {}
        onObjectAdded: Qt.callLater(root.countCovering)
        onObjectRemoved: Qt.callLater(root.countCovering)
    }
    property int coveringWindows: 0
    function countCovering(): void {
        let n = 0;
        for (let i = 0; i < windowStates.count; ++i) {
            const w = windowStates.objectAt(i) as WindowState;
            if (w && w.covers) {
                ++n;
            }
        }
        coveringWindows = n;
    }
    // "Show desktop" hides every window without minimizing it.
    readonly property bool covered: coveringWindows > 0 && !KWindowSystem.showingDesktop

    // The lock screen (KWin's screen locker on the session bus). While locked KWin draws no
    // desktop at all, so this only saves the sensor work.
    property bool sessionLocked: false
    DBus.DBusServiceWatcher {
        id: screenSaverService
        busType: DBus.BusType.Session
        watchedService: "org.freedesktop.ScreenSaver"
        // Asked only while the service is there, so the call never starts one.
        onRegisteredChanged: root.readLockState()
        Component.onCompleted: root.readLockState()
    }
    DBus.SignalWatcher {
        busType: DBus.BusType.Session
        service: "org.freedesktop.ScreenSaver"
        path: "/ScreenSaver"
        iface: "org.freedesktop.ScreenSaver"
        function dbusActiveChanged(active) {
            root.sessionLocked = active === true;
        }
    }
    function readLockState(): void {
        if (!screenSaverService.registered) {
            sessionLocked = false;
            return;
        }
        DBus.SessionBus.asyncCall({
            "service": "org.freedesktop.ScreenSaver",
            "path": "/ScreenSaver",
            "iface": "org.freedesktop.ScreenSaver",
            "member": "GetActive"
        }, reply => {
            root.sessionLocked = reply.value === true;
        }, () => {
            root.sessionLocked = false;
        });
    }

    readonly property bool sampling: cardShown && !hiddenByLayout && !covered && !sessionLocked

    // ksystemstats stops reading CPU and memory while nobody subscribes, so after a pause (and at
    // start) its first reply is the value from before the pause and its first CPU tick the average
    // over the pause; ticks come every 500 ms. For the first 1.5 s every tick is taken, so the
    // card shows current values about 1 s after it can be seen again, then one per interval.
    property bool catchingUp: false
    Timer {
        id: catchUp
        interval: 1500
        onTriggered: root.catchingUp = false
    }
    onSamplingChanged: {
        catchingUp = sampling;
        if (sampling) {
            catchUp.restart();
        } else {
            catchUp.stop();
        }
        console.debug(log, "sampling", sampling, "shown", cardShown, "covering", coveringWindows,
                      "showingDesktop", KWindowSystem.showingDesktop, "locked", sessionLocked,
                      "interval", updateInterval, "at", Date.now());
    }
    onUpdateIntervalChanged: console.debug(log, "interval", updateInterval, "tier", powerTier, "at", Date.now())
    readonly property int rateLimit: catchingUp ? 0 : updateInterval
    // A glide only while the card is seen, after the catch-up, and with animations on
    // (AnimationDurationFactor 0 makes longDuration 1 ms).
    readonly property bool glideAllowed: sampling && !catchingUp && Kirigami.Units.longDuration > 1

    Sensors.Sensor {
        id: cpuSensor
        sensorId: "cpu/all/usage"
        enabled: root.sampling
        updateRateLimit: root.rateLimit
        onValueChanged: console.debug(log, "cpu", cpuSensor.value, "at", Date.now())
    }
    Sensors.Sensor {
        id: memUsed
        sensorId: "memory/physical/used"
        enabled: root.sampling
        updateRateLimit: root.rateLimit
    }
    Sensors.Sensor {
        id: memTotal
        sensorId: "memory/physical/total"
        enabled: root.sampling
        updateRateLimit: root.rateLimit
    }

    readonly property bool cpuValid: typeof cpuSensor.value === "number" && isFinite(cpuSensor.value)
    readonly property real cpu: cpuValid ? Math.max(0, Math.min(100, cpuSensor.value)) : 0
    readonly property bool memValid: typeof memUsed.value === "number" && typeof memTotal.value === "number"
                                     && memTotal.value > 0
    readonly property real memFraction: memValid ? Math.max(0, Math.min(1, memUsed.value / memTotal.value)) : 0

    readonly property real gib: 1024 * 1024 * 1024
    readonly property string cpuText: cpuValid ? i18nc("@label CPU load in percent", "%1%", Math.round(cpu)) : "–"
    readonly property string memoryText: {
        if (!memValid) {
            return "–";
        }
        const used = memUsed.value / gib;
        // The installed size: the kernel reports a little less than the modules hold (firmware
        // and graphics reservations), so the total is rounded up to whole GB.
        const total = memTotal.value / gib;
        const totalText = total >= 2 ? Math.ceil(total - 0.05).toString() : Qt.locale().toString(total, "f", 1);
        return i18nc("@label used / total memory in GB, e.g. 6.1 / 16 GB", "%1 / %2 GB",
                     Qt.locale().toString(used, "f", 1), totalText);
    }

    Plasmoid.icon: "utilities-system-monitor"
    toolTipMainText: i18nc("@title", "CPU and memory")

    P5Support.DataSource {
        id: launcher
        engine: "executable"
        onNewData: sourceName => disconnectSource(sourceName)
    }

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18nc("@action", "Open System Monitor")
            icon.name: "utilities-system-monitor"
            // kstart hands the application to KIO and exits, so nothing stays a child of the shell.
            onTriggered: launcher.connectSource("kstart --application org.kde.plasma-systemmonitor")
        }
    ]

    fullRepresentation: FocusScope {
        id: card

        // The minimum never exceeds the board size: the desktop keeps a widget at least as large
        // as its minimum and stores the enlarged geometry, so a text size seen only for a moment
        // (the shell's font while a Global Theme is being applied) would grow the card for good.
        // The layout script gives the card the scaled size (docs/parts/desktop-cards.md).
        Layout.minimumWidth: Math.min(root.contentWidth, root.boardWidth)
        Layout.minimumHeight: Math.min(root.contentHeight, root.boardHeight)
        Layout.preferredWidth: root.contentWidth
        Layout.preferredHeight: root.contentHeight
        // 1 px of slack: the snapped sizes at fractional scales are a fraction of a pixel larger.
        readonly property real fitScale: Math.min(1, (width + 1) / root.contentWidth, (height + 1) / root.contentHeight)

        // Shown: visible (with every parent: the desktop hides the containment of another
        // activity) in a visible window.
        Binding {
            target: root
            property: "cardShown"
            value: card.visible && card.Window.window !== null && card.Window.window.visible
        }

        CardPalette { id: cardPalette }

        // Where the card ends on the desktop (see "Room on the desktop"): read again whenever
        // the card or its place changes.
        function reportBottom(): void {
            if (card.Window.window) {
                root.cardBottom = card.mapToItem(null, 0, card.height).y + 14;
            }
        }
        onHeightChanged: Qt.callLater(reportBottom)
        onVisibleChanged: Qt.callLater(reportBottom)
        Component.onCompleted: Qt.callLater(reportBottom)
        Connections {
            target: root.parent
            ignoreUnknownSignals: true
            function onYChanged() {
                Qt.callLater(card.reportBottom);
            }
            function onHeightChanged() {
                Qt.callLater(card.reportBottom);
            }
        }
        Connections {
            target: root
            function onRoomChanged() {
                Qt.callLater(card.reportBottom);
            }
        }

        component Meter: ColumnLayout {
            id: meter
            property string label
            property string value
            property real fraction: 0
            property color barColor

            Layout.fillWidth: true
            spacing: m.px(5)
            Accessible.role: Accessible.ProgressBar
            Accessible.name: label + " " + value

            RowLayout {
                Layout.fillWidth: true
                spacing: m.px(8)
                CardText {
                    pal: cardPalette
                    metrics: m
                    Layout.fillWidth: true
                    px: 12
                    weight: 700
                    color: cardPalette.label
                    text: meter.label
                }
                CardText {
                    pal: cardPalette
                    metrics: m
                    px: 12
                    weight: 700
                    tabular: true
                    text: meter.value
                }
            }
            // 5 px track and bar, radius 3 (board).
            Rectangle {
                id: track
                Layout.fillWidth: true
                Layout.preferredHeight: 5
                radius: 2.5
                antialiasing: true
                color: cardPalette.tint(0.10)

                // Whole pixels, so a change too small to see changes nothing.
                readonly property real target: meter.fraction > 0 ? Math.max(height, Math.round(width * meter.fraction)) : 0
                // The value the bar last moved to.
                property real shownFraction: 0
                // Each glide frame redraws the whole desktop (about 12 frames per glide), so the
                // bar steps in one frame; only a change of 10 points or more (CPU 4 % -> 14 %),
                // which idle jitter never makes, glides.
                onTargetChanged: {
                    const jump = Math.abs(meter.fraction - shownFraction) >= 0.1;
                    shownFraction = meter.fraction;
                    glide.stop();
                    if (root.glideAllowed && jump && bar.width > 0) {
                        glide.to = target;
                        glide.start();
                    } else {
                        bar.width = target;
                    }
                    console.debug(log, "bar", meter.label, glide.running ? "glide" : "step", target, "at", Date.now());
                }
                // A new width of the card (edit mode) applies at once.
                onWidthChanged: {
                    glide.stop();
                    bar.width = target;
                }

                Rectangle {
                    id: bar
                    width: 0
                    height: parent.height
                    radius: 2.5
                    antialiasing: true
                    color: meter.barColor
                }
                NumberAnimation {
                    id: glide
                    target: bar
                    property: "width"
                    duration: Kirigami.Units.longDuration
                    easing.type: Easing.OutCubic
                }
            }
        }

        ColumnLayout {
            // Board: 16 px padding + 1 px edge from the card side (the style's frame gives 14).
            // Laid out across the card; when the desktop gave the card less than this text size
            // needs (the text size was raised after the layout was made), laid out at the size
            // it needs and scaled down to fit, so nothing is cut off.
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            width: (card.fitScale < 1 ? root.contentWidth : parent.width) - 2 * 3
            scale: card.fitScale
            spacing: m.px(10)
            visible: !root.hiddenByLayout

            Meter {
                label: i18nc("@label processor load", "CPU")
                value: root.cpuText
                fraction: root.cpu / 100
                barColor: cardPalette.cpu
            }
            Meter {
                label: i18nc("@label", "Memory")
                value: root.memoryText
                fraction: root.memFraction
                barColor: cardPalette.memory
            }
        }
    }
}
