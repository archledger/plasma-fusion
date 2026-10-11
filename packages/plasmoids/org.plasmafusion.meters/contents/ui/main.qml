/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.workspace.dbus as DBus
import org.kde.kirigami as Kirigami
import org.kde.kwindowsystem
import org.kde.taskmanager as TaskManager

import "../code/glyphs.js" as Glyphs
import "../code/meters.js" as Meters

// System meters for the top bar (docs/parts/shell-meters.md): the processor load, the memory in
// use, the download and upload rates and the processor temperature, each optional, in one pill
// drawn like the quick settings status pill (Main / MainLight boards: 26 px, radius 13, ink .08,
// padding 0 12, gap 10, 16 px line glyphs, 12 px 700 figures). A click on a meter opens a small
// pop-up with a few more values and a button for System Monitor.
//
// The widget is in no layout: nothing changes until the user adds it (Add Widgets, or the
// Plasma Fusion settings page's "System meters in the top bar"). Its values come from
// ksystemstats through org.kde.ksysguard.sensors, as the system card's (Readings.qml), and it
// takes them as the card does (docs/parts/desktop-cards.md, "CARD-1"): one value per interval
// (2 s by default, x 2 in power saver and x 4 on critical battery: the hidden powerTier key the
// power service writes), and no sensor at all while the meters cannot be seen (a full-screen
// window over the bar, the session locked, the width budget hiding them) or are all turned off.
// Every figure sits in a box as wide as its widest value, so a new value never changes the
// widget's width and the bar is never laid out again for it.
PlasmoidItem {
    id: root

    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    readonly property bool inPanel: [PlasmaCore.Types.TopEdge, PlasmaCore.Types.RightEdge,
        PlasmaCore.Types.BottomEdge, PlasmaCore.Types.LeftEdge].indexOf(Plasmoid.location) !== -1

    // Colours: the colour scheme's text and its warning (neutral) and error (negative) text, so
    // the High Contrast scheme's colours apply; the pill's ink as the clock pill's.
    readonly property bool dark: {
        const c = Kirigami.Theme.backgroundColor;
        return (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) < 0.5;
    }
    readonly property color textColor: Kirigami.Theme.textColor
    readonly property color ink: dark ? "#ffffff" : Kirigami.Theme.textColor
    function tint(alpha: real): color {
        return Qt.rgba(ink.r, ink.g, ink.b, alpha);
    }
    function levelColor(level: int): color {
        return level >= 2 ? Kirigami.Theme.negativeTextColor : level === 1 ? Kirigami.Theme.neutralTextColor : textColor;
    }

    FusionTablet {
        id: tabletState
    }
    Motion {
        id: motion
    }
    // The user's accent: the open pill and the focus rings.
    FusionAccent {
        id: accent
    }
    // Text scale and pixel grid of the panel window.
    FusionMetrics {
        id: m
        area: Plasmoid.containment ? Plasmoid.containment.availableScreenRect : Qt.rect(0, 0, 1440, 900)
        tablet: tabletState.tablet
    }

    // ---- Settings
    readonly property var meters: Meters.shown(Plasmoid.configuration.showCpu, Plasmoid.configuration.showMemory,
                                               Plasmoid.configuration.showNetwork, Plasmoid.configuration.showTemperature)
    readonly property int powerTier: Math.max(0, Math.min(2, Plasmoid.configuration.powerTier))
    readonly property int updateInterval: Meters.interval(Plasmoid.configuration.updateInterval, powerTier)
    // Degrees Fahrenheit where the region measures in US units.
    readonly property bool fahrenheit: Qt.locale().measurementSystem === Locale.ImperialUSSystem

    // ---- The top bar's width budget (the clock pill's WidthBudget.qml, ADAPTIVE 5.1): the
    // network meter, the widest, leaves the bar at step 1 (with the global menu's compact view),
    // the others at step 2 (with phone and clipboard), before anything the bar needs. Tablet
    // posture starts at step 2, so the meters are not in the tablet bar.
    property int budgetLevel: 0
    readonly property bool budgeted: inPanel && !vertical
    readonly property bool budgetHidden: budgeted && budgetLevel >= 2
    function budgetSaving(level: int): real {
        if (!budgeted || level <= 0) {
            return 0;
        }
        return Math.ceil(pillWidthFor(cellsAt(0)) - (level >= 2 ? 0 : pillWidthFor(cellsAt(level))));
    }

    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    // The whole bar height is the hit area.
    Plasmoid.constraintHints: Plasmoid.CanFillArea
    Plasmoid.status: popupOpen ? PlasmaCore.Types.RequiresAttentionStatus : PlasmaCore.Types.ActiveStatus
    Plasmoid.icon: "utilities-system-monitor"
    activationTogglesExpanded: false
    hideOnWindowDeactivate: true
    toolTipMainText: ""
    toolTipSubText: ""

    Layout.minimumWidth: vertical ? -1 : (budgetHidden ? 0 : pillWidth)
    Layout.preferredWidth: vertical ? -1 : (budgetHidden ? 0 : pillWidth)
    Layout.maximumWidth: vertical ? Infinity : (budgetHidden ? 0 : pillWidth)
    Layout.minimumHeight: vertical ? pillHeight : -1
    Layout.preferredHeight: vertical ? pillHeight : -1
    Layout.maximumHeight: vertical ? pillHeight : Infinity

    // ---- Sizes (board values, scaled with the text). Every width is worked out from the font,
    // never read from laid-out items, so it is the same while the meters are hidden.
    readonly property real padding: m.px(12)
    readonly property real gap: m.px(10)
    readonly property real glyph: m.px(16)
    readonly property real glyphGap: m.px(5)
    // Between the network meter's download and upload figures: wider than glyph to figure.
    readonly property real pairGap: 2 * glyphGap + m.px(2)
    // The network meter's arrows are narrow: their glyphs sit in 10 px boxes.
    readonly property real arrowBox: m.px(10)
    // Drawn height of the pill: 26 px, never taller than the panel row.
    readonly property real pillHeight: vertical ? m.px(26) : Math.min(m.px(26), Math.max(1, height))

    FontMetrics {
        id: figures
        font.family: m.family
        font.pixelSize: m.font(12)
        font.weight: Font.Bold
        font.features: { "tnum": 1 }
    }
    // The widest digit of the font (tabular figures make them equal where the font has them).
    readonly property string widestDigit: {
        let widest = "0";
        for (const d of "0123456789") {
            if (figures.advanceWidth(d) > figures.advanceWidth(widest)) {
                widest = d;
            }
        }
        return widest;
    }
    function boxFor(samples: var): real {
        let width = 0;
        for (const s of samples) {
            width = Math.max(width, figures.advanceWidth(s.replace(/[0-9]/g, widestDigit)));
        }
        return Math.ceil(width);
    }
    readonly property real percentBox: boxFor([percentText(100)])
    readonly property real temperatureBox: boxFor([temperatureText(188)])
    readonly property real rateBox: boxFor(Meters.rateSamples().map(s => rateText(s, true)))
    function meterWidth(kind: string): real {
        switch (kind) {
        case "cpu":
        case "memory":
            return glyph + glyphGap + percentBox;
        case "temperature":
            return glyph + glyphGap + temperatureBox;
        case "network":
            return 2 * (arrowBox + glyphGap + rateBox) + pairGap;
        }
        return glyph;
    }
    // The temperature meter shows once a reading came: ksystemstats has the sensor everywhere but
    // reads 0 where the machine has no CPU temperature sensor (virtual machines, some ARM boards).
    property bool temperatureSeen: false
    // The meters in the bar at a budget step; with none, one glyph that still opens the pop-up.
    function cellsAt(level: int): var {
        const list = meters.filter(kind => !(kind === "network" && budgeted && level >= 1)
                                           && !(kind === "temperature" && !temperatureSeen));
        return list.length > 0 ? list : ["none"];
    }
    function pillWidthFor(list: var): real {
        let width = 2 * padding + gap * (list.length - 1);
        for (const kind of list) {
            width += meterWidth(kind);
        }
        return m.snap(width);
    }
    readonly property var cells: cellsAt(budgetLevel)
    readonly property real pillWidth: pillWidthFor(cells)

    // ---- Texts
    function percentText(value: real): string {
        return isNaN(value) ? "–" : i18nc("@label percent in the bar, e.g. 23%", "%1%", value);
    }
    function temperatureText(value: real): string {
        return isNaN(value) ? "–" : i18nc("@label temperature in whole degrees in the bar, e.g. 52°", "%1°", value);
    }
    function unitText(unit: string): string {
        switch (unit) {
        case "kB":
            return i18nc("@label network rate unit, kilobytes per second", "kB/s");
        case "MB":
            return i18nc("@label network rate unit, megabytes per second", "MB/s");
        case "GB":
            return i18nc("@label network rate unit, gigabytes per second", "GB/s");
        case "TB":
            return i18nc("@label network rate unit, terabytes per second", "TB/s");
        }
        return i18nc("@label network rate unit, bytes per second", "B/s");
    }
    // In the bar the arrows say it is a rate, so the unit drops "/s" there ("1.2 MB").
    function shortUnitText(unit: string): string {
        switch (unit) {
        case "kB":
            return i18nc("@label network rate unit in the bar, kilobytes (per second)", "kB");
        case "MB":
            return i18nc("@label network rate unit in the bar, megabytes (per second)", "MB");
        case "GB":
            return i18nc("@label network rate unit in the bar, gigabytes (per second)", "GB");
        case "TB":
            return i18nc("@label network rate unit in the bar, terabytes (per second)", "TB");
        }
        return i18nc("@label network rate unit in the bar, bytes (per second)", "B");
    }
    function rateText(r: var, compact: bool): string {
        if (!r) {
            return "–";
        }
        return i18nc("@label network rate: number and unit, e.g. 1.2 MB/s", "%1 %2",
                     Qt.locale().toString(r.value, "f", r.decimals), compact ? shortUnitText(r.unit) : unitText(r.unit));
    }
    function degreesText(value: real): string {
        return fahrenheit ? i18nc("@label temperature in degrees Fahrenheit", "%1 °F", value)
                          : i18nc("@label temperature in degrees Celsius", "%1 °C", value);
    }

    readonly property real cpuPercent: Meters.percent(meterReadings.cpu)
    readonly property real memoryPercent: Meters.percent(Meters.memoryFraction(meterReadings.memoryUsed, meterReadings.memoryTotal) * 100)
    readonly property real degrees: Meters.temperature(meterReadings.temperature, fahrenheit)
    readonly property var downRate: Meters.rate(meterReadings.download)
    readonly property var upRate: Meters.rate(meterReadings.upload)

    // Warning levels (meters.js: limits with a 5 point fall-back), for the colour and the names.
    property int cpuLevel: 0
    property int memoryLevel: 0
    property int temperatureLevel: 0
    onCpuPercentChanged: cpuLevel = Meters.level("cpu", cpuPercent, cpuLevel)
    onMemoryPercentChanged: memoryLevel = Meters.level("memory", memoryPercent, memoryLevel)
    // Limits in °C whatever the region shows.
    readonly property real celsius: Meters.temperatureValid(meterReadings.temperature) ? Math.round(meterReadings.temperature) : NaN
    onCelsiusChanged: {
        temperatureLevel = Meters.level("temperature", celsius, temperatureLevel);
        if (!isNaN(celsius)) {
            temperatureSeen = true;
        }
    }

    function levelSuffix(name: string, level: int): string {
        return level >= 2 ? i18nc("@info accessible name of a meter at a critical value, %1 the meter and value", "%1, very high", name)
             : level === 1 ? i18nc("@info accessible name of a meter at a high value, %1 the meter and value", "%1, high", name)
             : name;
    }
    function accessibleName(kind: string): string {
        switch (kind) {
        case "cpu":
            return isNaN(cpuPercent) ? i18nc("@info accessible", "CPU, no value yet")
                                     : levelSuffix(i18nc("@info accessible", "CPU %1%", cpuPercent), cpuLevel);
        case "memory":
            return isNaN(memoryPercent) ? i18nc("@info accessible", "Memory, no value yet")
                                        : levelSuffix(i18nc("@info accessible", "Memory %1% used", memoryPercent), memoryLevel);
        case "network":
            return !downRate || !upRate ? i18nc("@info accessible", "Network, no value yet")
                                        : i18nc("@info accessible", "Network: download %1, upload %2", rateText(downRate, false), rateText(upRate, false));
        case "temperature":
            return isNaN(degrees) ? i18nc("@info accessible", "CPU temperature, no reading")
                                  : levelSuffix(i18nc("@info accessible", "CPU temperature %1", degreesText(degrees)), temperatureLevel);
        }
        return i18nc("@action:button", "System meters");
    }
    function meterTitle(kind: string): string {
        switch (kind) {
        case "cpu":
            return i18nc("@info:tooltip", "Processor load");
        case "memory":
            return i18nc("@info:tooltip", "Memory in use");
        case "network":
            return i18nc("@info:tooltip", "Network");
        case "temperature":
            return i18nc("@info:tooltip", "Processor temperature (hottest core)");
        }
        return i18nc("@info:tooltip", "System meters");
    }

    // ---- When the meters can be seen
    // Set by the pill: shown in a visible window.
    property bool pillShown: false
    // A full-screen window on this bar's screen (current virtual desktop and activity) covers the
    // bar; a maximized one leaves it visible. The same model as the system card's.
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
        readonly property bool covers: model.IsFullScreen === true
        onCoversChanged: Qt.callLater(root.countCovering)
    }
    Instantiator {
        id: windowStates
        // Only while the bar is in a panel and a meter is on: the desktop has no bar to cover.
        model: root.inPanel && root.meters.length > 0 ? screenWindows : null
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
    readonly property bool covered: coveringWindows > 0 && !KWindowSystem.showingDesktop

    // The lock screen (KWin's screen locker on the session bus), as the system card follows it.
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

    // A bar without a screen (left over from a screen that is gone) keeps a window, but nobody
    // sees it.
    readonly property bool onScreen: !Plasmoid.containment || Plasmoid.containment.screen >= 0
    readonly property bool barSeen: pillShown && onScreen && !budgetHidden && !covered
    readonly property bool sampling: !sessionLocked && (popupOpen || (barSeen && meters.length > 0))

    // ksystemstats reads nothing while nobody subscribes, so after a pause (and at start) its
    // first reply is the value from before the pause; for 1.5 s every tick (500 ms) is taken, so
    // the meters are current about 1 s after they can be seen again, then one value per interval.
    property bool catchingUp: false
    Timer {
        id: catchUp
        interval: 1500
        onTriggered: root.catchingUp = false
    }
    // The pop-up's extra sensors start the same way when it opens.
    function startCatchUp(): void {
        catchingUp = true;
        catchUp.restart();
    }
    onPopupOpenChanged: {
        if (popupOpen && sampling) {
            startCatchUp();
        }
    }
    onSamplingChanged: {
        if (sampling) {
            startCatchUp();
        } else {
            catchingUp = false;
            catchUp.stop();
        }
        console.debug(log, "sampling", sampling, "shown", pillShown, "covering", coveringWindows, "locked", sessionLocked,
                      "hidden", budgetHidden, "interval", updateInterval, "at", Date.now());
    }

    // Debug output for tests: QT_LOGGING_RULES="org.plasmafusion.meters.debug=true".
    LoggingCategory {
        id: log
        name: "org.plasmafusion.meters"
        defaultLogLevel: LoggingCategory.Warning
    }

    Readings {
        id: meterReadings
        active: root.sampling
        // The meters in the bar now (the width budget may have taken some out); the temperature
        // as soon as it is turned on, to learn whether there is a reading.
        cpuWanted: root.cells.indexOf("cpu") !== -1
        memoryWanted: root.cells.indexOf("memory") !== -1
        networkWanted: root.cells.indexOf("network") !== -1
        temperatureWanted: Plasmoid.configuration.showTemperature
        details: root.popupOpen
        rateLimit: root.catchingUp ? 0 : root.updateInterval
        onValueArrived: sensorId => console.debug(log, "value", sensorId, "at", Date.now())
    }

    // ---- System Monitor
    P5Support.DataSource {
        id: launcher
        engine: "executable"
        onNewData: sourceName => disconnectSource(sourceName)
    }
    function openSystemMonitor(): void {
        setPopupOpen(false);
        // kstart hands the application to KIO and exits, so nothing stays a child of the shell.
        launcher.connectSource("kstart --application org.kde.plasma-systemmonitor");
    }
    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18nc("@action", "Open System Monitor")
            icon.name: "utilities-system-monitor"
            onTriggered: root.openSystemMonitor()
        }
    ]

    // ---- The pop-up
    property bool popupOpen: false
    property bool openOnPress: false
    function setPopupOpen(open: bool): void {
        popupOpen = open;
    }
    Connections {
        target: Plasmoid
        function onActivated() {
            root.setPopupOpen(!root.popupOpen);
        }
    }
    // After the pop-up closed itself (focus moved elsewhere), follow its state a little later,
    // so that the click on a meter that caused the close does not open it again.
    Timer {
        id: closeSync
        interval: 150
        onTriggered: {
            if (!popup.visible) {
                root.popupOpen = false;
            }
        }
    }

    // ---- The pill
    Item {
        id: pill

        anchors.centerIn: parent
        width: root.pillWidth
        height: root.vertical ? root.pillHeight : root.height
        visible: !root.budgetHidden

        Binding {
            target: root
            property: "pillShown"
            value: pill.visible && pill.Window.window !== null && pill.Window.window.visible
        }

        readonly property bool hovered: {
            for (let i = 0; i < meterRepeater.count; ++i) {
                const b = meterRepeater.itemAt(i) as MeterButton;
                if (b && b.hovered) {
                    return true;
                }
            }
            return false;
        }
        readonly property bool pressed: {
            for (let i = 0; i < meterRepeater.count; ++i) {
                const b = meterRepeater.itemAt(i) as MeterButton;
                if (b && b.down) {
                    return true;
                }
            }
            return false;
        }

        Rectangle {
            id: background
            anchors.centerIn: parent
            width: parent.width
            height: root.pillHeight
            radius: height / 2
            antialiasing: true
            color: root.popupOpen ? accent.soft(0.35) : root.tint(pill.pressed ? 0.16 : pill.hovered ? 0.12 : 0.08)
            border.width: root.popupOpen ? 1 : 0
            border.color: Qt.rgba(accent.focusRing.r, accent.focusRing.g, accent.focusRing.b, 0.5)
            Behavior on color {
                enabled: motion.animate
                ColorAnimation { duration: motion.hover }
            }
        }

        Row {
            anchors.fill: parent
            LayoutMirroring.enabled: Application.layoutDirection === Qt.RightToLeft
            LayoutMirroring.childrenInherit: true
            Repeater {
                id: meterRepeater
                model: root.cells
                delegate: MeterButton {}
            }
        }
    }

    // One meter: its glyph and figure, a button that opens the pop-up. It reaches half the gap to
    // its neighbours and the pill's edge, so the whole pill is clickable.
    component MeterButton: T.AbstractButton {
        id: meter

        required property string modelData
        required property int index
        readonly property string kind: modelData
        readonly property real leading: index === 0 ? root.padding : root.gap / 2
        readonly property real trailing: index === root.cells.length - 1 ? root.padding : root.gap / 2

        width: leading + root.meterWidth(kind) + trailing
        height: pill.height
        focusPolicy: Qt.TabFocus
        hoverEnabled: true
        text: root.accessibleName(kind)
        Accessible.name: text
        Accessible.description: i18nc("@info:whatsthis", "Show the system details")
        Accessible.role: Accessible.ButtonDropDown
        padding: 0
        Keys.onReturnPressed: root.setPopupOpen(!root.popupOpen)
        Keys.onEnterPressed: root.setPopupOpen(!root.popupOpen)
        onPressed: root.openOnPress = !root.popupOpen
        onClicked: root.setPopupOpen(root.openOnPress)

        background: Item {
            // Keyboard focus: a 2 px ring around this meter's part of the pill, 4 px outside it at
            // the pill's ends.
            Rectangle {
                anchors.fill: parent
                anchors.leftMargin: meter.index === 0 ? -4 : 0
                anchors.rightMargin: meter.index === root.cells.length - 1 ? -4 : 0
                anchors.topMargin: (parent.height - root.pillHeight) / 2 - 4
                anchors.bottomMargin: anchors.topMargin
                radius: height / 2
                color: "transparent"
                border.width: 2
                border.color: accent.focusRing
                visible: meter.visualFocus
            }
        }

        contentItem: Item {
            Row {
                x: meter.leading
                anchors.verticalCenter: parent.verticalCenter
                spacing: root.glyphGap

                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    width: meter.kind === "network" ? root.arrowBox : root.glyph
                    height: root.glyph
                    LineIcon {
                        anchors.centerIn: parent
                        size: root.glyph
                        color: valueText.color
                        path: meter.kind === "cpu" ? Glyphs.cpu
                            : meter.kind === "memory" ? Glyphs.memory
                            : meter.kind === "network" ? Glyphs.download
                            : meter.kind === "temperature" ? Glyphs.thermometer : Glyphs.gauge
                    }
                }
                FusionText {
                    id: valueText
                    anchors.verticalCenter: parent.verticalCenter
                    visible: meter.kind !== "none"
                    width: meter.kind === "network" ? root.rateBox : meter.kind === "temperature" ? root.temperatureBox : root.percentBox
                    metrics: m
                    px: 12
                    weight: 700
                    font.features: { "tnum": 1 }
                    color: meter.kind === "cpu" ? root.levelColor(root.cpuLevel)
                         : meter.kind === "memory" ? root.levelColor(root.memoryLevel)
                         : meter.kind === "temperature" ? root.levelColor(root.temperatureLevel) : root.textColor
                    text: meter.kind === "cpu" ? root.percentText(root.cpuPercent)
                        : meter.kind === "memory" ? root.percentText(root.memoryPercent)
                        : meter.kind === "temperature" ? root.temperatureText(root.degrees)
                        : meter.kind === "network" ? root.rateText(root.downRate, true) : ""
                }
                // The network meter's second pair: upload (the Row's two spacings and this make
                // pairGap).
                Item {
                    visible: meter.kind === "network"
                    width: root.pairGap - 2 * root.glyphGap
                    height: 1
                }
                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: meter.kind === "network"
                    width: root.arrowBox
                    height: root.glyph
                    LineIcon {
                        anchors.centerIn: parent
                        size: root.glyph
                        color: root.textColor
                        path: Glyphs.upload
                    }
                }
                FusionText {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: meter.kind === "network"
                    width: root.rateBox
                    metrics: m
                    px: 12
                    weight: 700
                    font.features: { "tnum": 1 }
                    color: root.textColor
                    text: root.rateText(root.upRate, true)
                }
            }
        }

        PlasmaCore.ToolTipArea {
            anchors.fill: parent
            // Touch synthesises hover: no tooltips in tablet posture.
            active: !root.popupOpen && !tabletState.tablet
            location: Plasmoid.location
            mainText: root.meterTitle(meter.kind)
            subText: meter.kind === "none" ? i18nc("@info:tooltip", "Turn meters on in the widget's settings") : meter.text
        }
    }

    PlasmaCore.AppletPopup {
        id: popup

        visualParent: pill
        popupDirection: {
            switch (Plasmoid.location) {
            case PlasmaCore.Types.BottomEdge:
                return Qt.TopEdge;
            case PlasmaCore.Types.LeftEdge:
                return Qt.RightEdge;
            case PlasmaCore.Types.RightEdge:
                return Qt.LeftEdge;
            default:
                return Qt.BottomEdge;
            }
        }
        margin: Plasmoid.configuration.popupGap
        floating: !root.inPanel
        removeBorderStrategy: PlasmaCore.AppletPopup.Never
        hideOnWindowDeactivate: true
        // Only under a pill that is shown in a window: a widget in a bar without a screen (a bar
        // left over from a screen that is gone) has nothing to place it under.
        visible: root.popupOpen && root.pillShown && root.onScreen && details.status === Loader.Ready

        onVisibleChanged: {
            if (visible) {
                popup.requestActivate();
                (details.item as MetersPopup)?.forceActiveFocus();
            } else {
                closeSync.restart();
            }
        }

        mainItem: Loader {
            id: details
            // Built on the first open, kept afterwards.
            active: root.popupOpen || item !== null
            focus: true
            sourceComponent: MetersPopup {
                readings: meterReadings
                host: root
                focus: true
                onCloseRequested: root.setPopupOpen(false)
                onOpenMonitorRequested: root.openSystemMonitor()
            }
        }
    }

    // ---- Testing hooks (config key debugAction, cleared after use): "dump:TAG" logs the meters
    // (what is subscribed, the texts and the accessible names, the pill's place in the window),
    // "open" and "close" the pop-up.
    readonly property string debugAction: Plasmoid.configuration.debugAction
    onDebugActionChanged: Qt.callLater(runDebugAction)
    function runDebugAction(): void {
        const action = Plasmoid.configuration.debugAction;
        if (!action) {
            return;
        }
        Plasmoid.configuration.debugAction = "";
        const parts = action.split(":");
        if (parts[0] === "open" || parts[0] === "close") {
            setPopupOpen(parts[0] === "open");
        } else if (parts[0] === "dump") {
            const names = [];
            const texts = [];
            for (let i = 0; i < meterRepeater.count; ++i) {
                const b = meterRepeater.itemAt(i) as MeterButton;
                if (b) {
                    names.push(b.Accessible.name);
                }
            }
            for (const kind of cells) {
                texts.push(kind === "cpu" ? percentText(cpuPercent) : kind === "memory" ? percentText(memoryPercent)
                         : kind === "temperature" ? temperatureText(degrees)
                         : kind === "network" ? rateText(downRate, true) + " / " + rateText(upRate, true) : "");
            }
            const at = pill.mapToItem(null, 0, 0);
            console.info("meters: dump " + parts.slice(1).join(":") + " " + JSON.stringify({
                sampling: sampling, meters: meters, subscribed: meterReadings.subscribed, interval: updateInterval,
                rateLimit: meterReadings.rateLimit, covered: covered, locked: sessionLocked, budgetLevel: budgetLevel,
                texts: texts, names: names, levels: [cpuLevel, memoryLevel, temperatureLevel],
                raw: { cpu: meterReadings.cpu, memoryUsed: meterReadings.memoryUsed, memoryTotal: meterReadings.memoryTotal,
                       download: meterReadings.download, upload: meterReadings.upload, temperature: meterReadings.temperature },
                pill: { x: Math.round(at.x), y: Math.round(at.y), width: Math.round(pill.width), height: Math.round(root.pillHeight) },
                popup: popupOpen && popup.visible ? { x: popup.x, y: popup.y, width: popup.width, height: popup.height } : null
            }));
        }
    }
}
