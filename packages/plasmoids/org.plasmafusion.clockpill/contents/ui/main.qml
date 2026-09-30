/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCMUtils
import org.kde.taskmanager as TaskManager
import org.kde.plasma.clock
import org.kde.plasma.workspace.dbus as DBus

import "../code/formats.js" as Formats

// Centre of the Plasma Fusion top bar (Main / MainLight boards): one pill, 24 px tall, radius
// 12, rgba(255,255,255,.08) (light: rgba(20,24,39,.08)), padding 0 12, gap 12, holding the
// workspace dots, the date (Manrope 13 px 700) and the time (Space Grotesk 13 px 600).
// A click on the date or time opens a calendar pop-up that floats below the bar like the
// quick-settings pop-up. Scrolling over the pill switches workspaces.
//
// The widget has no fullRepresentation: the pill is shown directly in the panel and the
// calendar is an own AppletPopup (gap below the bar, all corners rounded).
PlasmoidItem {
    id: root

    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    readonly property bool inPanel: [PlasmaCore.Types.TopEdge, PlasmaCore.Types.RightEdge,
        PlasmaCore.Types.BottomEdge, PlasmaCore.Types.LeftEdge].indexOf(Plasmoid.location) !== -1

    readonly property bool dark: {
        const c = Kirigami.Theme.backgroundColor;
        return (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) < 0.5;
    }
    readonly property color textColor: Kirigami.Theme.textColor
    readonly property color ink: dark ? "#ffffff" : Kirigami.Theme.textColor
    readonly property color focusColor: accent.focusRing
    function tint(alpha: real): color {
        return Qt.rgba(ink.r, ink.g, ink.b, alpha);
    }

    property bool popupOpen: false
    property bool openOnPress: false

    FusionTablet {
        id: tabletState
    }
    Motion {
        id: motion
    }
    // The user's accent (decision 3): the open pill and the focus ring.
    FusionAccent {
        id: accent
    }
    // Text scale and pixel grid of the panel window (docs/parts/shell-topbar.md, "Text scale").
    FusionMetrics {
        id: m
        area: Plasmoid.containment ? Plasmoid.containment.availableScreenRect : Qt.rect(0, 0, 1440, 900)
        tablet: tabletState.tablet
    }
    // The top bar's width budget (ADAPTIVE 5.1, set by the top bar, TOP-2): 0 the full pill,
    // 1 the short date, 2 the time only; the dots hide at step 6.
    property int compactLevel: 0
    property bool hideDots: false
    // Board padding and gap of the pill (12), scaled with the text.
    readonly property real pillPadding: m.px(12)

    // ---- Formats
    readonly property string timeFormat: Formats.timeFormat(Qt.locale().timeFormat(Locale.ShortFormat),
                                                            Plasmoid.configuration.use24hFormat,
                                                            Qt.locale().name)
    readonly property string dateFormat: Plasmoid.configuration.dateFormat === "custom"
        && Plasmoid.configuration.customDateFormat !== ""
        ? Plasmoid.configuration.customDateFormat
        : Formats.shortDateFormat(Qt.locale(), Qt.locale().dateFormat(Locale.LongFormat))

    // ---- Workspaces (current one per screen when workspaces are per output)
    property var currentDesktop: ""
    readonly property int desktopCount: desktopInfo.numberOfDesktops
    readonly property int currentIndex: desktopInfo.desktopIds.indexOf(currentDesktop)
    readonly property bool showDots: Plasmoid.configuration.showWorkspaces && desktopCount > 1 && !hideDots

    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    Plasmoid.constraintHints: Plasmoid.CanFillArea
    Plasmoid.status: popupOpen ? PlasmaCore.Types.RequiresAttentionStatus : PlasmaCore.Types.ActiveStatus
    activationTogglesExpanded: false
    hideOnWindowDeactivate: true
    toolTipMainText: ""
    toolTipSubText: ""

    // Centring: two expanding spacers put this widget near the middle of the bar, but they
    // work from the neighbours' size hints, and the stock global menu is wider than its hint
    // (the pill moved 8 px right whenever an application menu was shown). So the widget asks
    // for `centerSlack` px on both sides of the pill and places the pill itself on the middle
    // of the panel inside that room.
    readonly property bool centerInPanel: Plasmoid.configuration.centerInPanel
        && Plasmoid.formFactor === PlasmaCore.Types.Horizontal
    readonly property int centerSlack: centerInPanel ? 48 : 0

    Layout.minimumWidth: vertical ? -1 : pill.width
    Layout.preferredWidth: vertical ? -1 : pill.width + 2 * centerSlack
    Layout.maximumWidth: vertical ? Infinity : pill.width + 2 * centerSlack
    Layout.minimumHeight: vertical ? pill.height : -1
    Layout.preferredHeight: vertical ? pill.height : -1
    Layout.maximumHeight: vertical ? pill.height : Infinity

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18nc("@action:inmenu", "Adjust Date and Time…")
            icon.name: "preferences-system-time"
            onTriggered: KCMUtils.KCMLauncher.openSystemSettings("kcm_clock")
        },
        PlasmaCore.Action {
            text: i18nc("@action:inmenu", "Configure Virtual Desktops…")
            icon.name: "preferences-desktop-virtual"
            onTriggered: KCMUtils.KCMLauncher.openSystemSettings("kcm_kwin_virtualdesktops")
        }
    ]

    // The item the panel's layout positions (the applet container), watched for moves.
    property Item layoutCell: null
    function findLayoutCell(): Item {
        let candidate = root;
        while (candidate.parent) {
            if (candidate.parent instanceof GridLayout) {
                return candidate;
            }
            candidate = candidate.parent;
        }
        return null;
    }

    // Puts the pill on the middle of the panel window (the screen's middle for a full-width
    // bar), clamped to this widget's own area. Assigns pill.x only, which never feeds back
    // into any size hint.
    function placePill() {
        let x = (width - pill.width) / 2;
        if (centerInPanel && root.Window.window) {
            const origin = root.mapToItem(null, 0, 0);
            x = root.Window.window.width / 2 - origin.x - pill.width / 2;
        }
        pill.x = Math.round(Math.max(0, Math.min(width - pill.width, x)));
    }

    onWidthChanged: placePill()
    onCenterInPanelChanged: placePill()
    Connections {
        target: root.layoutCell
        function onXChanged() {
            root.placePill();
        }
    }
    Connections {
        target: root.Window.window
        function onWidthChanged() {
            root.placePill();
        }
    }

    // The calendar is not built at login (BACKLOG S2): it starts building in the background as
    // soon as the pointer enters the pill or anything presses it, so it is ready by the click;
    // the time from the first open request to its first frame is logged once.
    property bool calendarWanted: false
    property real openStarted: 0
    function prepareCalendar(): void {
        calendarWanted = true;
    }
    function setPopupOpen(open: bool) {
        if (open && openStarted === 0) {
            openStarted = Date.now();
        }
        calendarWanted = calendarWanted || open;
        popupOpen = open;
    }
    property bool calendarShown: false

    function refreshDesktop() {
        const screen = Plasmoid.containment ? Plasmoid.containment.screenGeometry : null;
        currentDesktop = screen && screen.width > 0
            ? desktopInfo.currentDesktopByScreenGeometry(screen)
            : desktopInfo.currentDesktop;
    }

    function switchToDesktop(index: int) {
        if (index < 0 || index >= desktopCount || index === currentIndex) {
            return;
        }
        // KWin numbers workspaces from 1 in their order, the order of desktopIds.
        DBus.SessionBus.asyncCall({
            "service": "org.kde.KWin",
            "path": "/KWin",
            "iface": "org.kde.KWin",
            "member": "setCurrentDesktop",
            "arguments": [new DBus.int32(index + 1)]
        }, () => {}, () => {});
    }

    function stepDesktop(step: int) {
        if (desktopCount < 2) {
            return;
        }
        let target = currentIndex + step;
        if (target < 0 || target >= desktopCount) {
            if (!desktopInfo.navigationWrappingAround) {
                return;
            }
            target = (target + desktopCount) % desktopCount;
        }
        switchToDesktop(target);
    }

    function showOverview() {
        DBus.SessionBus.asyncCall({
            "service": "org.kde.kglobalaccel",
            "path": "/component/kwin",
            "iface": "org.kde.kglobalaccel.Component",
            "member": "invokeShortcut",
            "arguments": ["Overview"]
        }, () => {}, () => {});
    }

    TaskManager.VirtualDesktopInfo {
        id: desktopInfo
        onCurrentDesktopChanged: root.refreshDesktop()
        onCurrentDesktopForScreenChanged: root.refreshDesktop()
        onDesktopIdsChanged: root.refreshDesktop()
    }

    Connections {
        target: Plasmoid.containment
        function onScreenGeometryChanged() {
            root.refreshDesktop();
        }
    }

    Component.onCompleted: {
        refreshDesktop();
        attachTimer.start();
    }
    onParentChanged: attachTimer.restart()

    // The shell puts the widget into its panel cell after creating it; look for the cell once
    // the item is in place (and again a few times while it is not).
    Timer {
        id: attachTimer
        property int attempts: 0
        interval: 250
        onTriggered: {
            root.layoutCell = root.findLayoutCell();
            root.placePill();
            if (!root.layoutCell && ++attempts < 20) {
                restart();
            }
        }
    }

    Clock {
        id: clock
        // No time zone: follows the system time zone.
    }

    // The time never changes the pill's width (BACKLOG M8): its box is as wide as the widest of
    // this time, 10:58 and 22:58 in the same format (two-digit hours, AM and PM), with every digit
    // the widest one.
    readonly property string timeText: Qt.locale().toString(clock.dateTime, root.timeFormat).replace(/\u202f/g, "\u2009")
    FontMetrics {
        id: timeMetrics
        font: timeLabel.font
    }
    readonly property real timeBoxWidth: {
        let widest = "0";
        for (const d of "0123456789") {
            if (timeMetrics.advanceWidth(d) > timeMetrics.advanceWidth(widest)) {
                widest = d;
            }
        }
        const format = t => Qt.locale().toString(t, root.timeFormat).replace(/\u202f/g, "\u2009");
        let width = 0;
        for (const sample of [timeText, format(new Date(2000, 0, 1, 10, 58)), format(new Date(2000, 0, 1, 22, 58))]) {
            width = Math.max(width, timeMetrics.advanceWidth(sample.replace(/[0-9]/g, widest)));
        }
        return Math.ceil(width);
    }

    Connections {
        target: Plasmoid
        function onActivated() {
            root.setPopupOpen(!root.popupOpen);
        }
    }

    // After the pop-up closed itself (focus moved elsewhere), follow its state a little later,
    // so that a click on the date that caused the close does not reopen it.
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

        anchors.verticalCenter: parent.verticalCenter
        width: row.implicitWidth
        // 24 px on the board (32 in tablet posture, TABLET T5), scaled with the text, never taller
        // than the panel row.
        readonly property real boardHeight: m.px(tabletState.tablet ? 32 : 24)
        height: root.vertical ? boardHeight : Math.min(boardHeight, Math.max(1, root.height))
        onWidthChanged: root.placePill()

        // Wheel over any part of the pill switches workspaces (one step per notch).
        WheelHandler {
            id: wheel
            property real accumulated: 0
            enabled: Plasmoid.configuration.wheelSwitchesWorkspaces && root.desktopCount > 1
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => {
                const delta = event.angleDelta.y !== 0 ? event.angleDelta.y : -event.angleDelta.x;
                if (delta * accumulated < 0) {
                    accumulated = 0;
                }
                accumulated += delta;
                while (accumulated >= 120) {
                    accumulated -= 120;
                    root.stepDesktop(-1);
                }
                while (accumulated <= -120) {
                    accumulated += 120;
                    root.stepDesktop(1);
                }
            }
        }

        Rectangle {
            id: background
            anchors.fill: parent
            radius: height / 2
            antialiasing: true
            color: root.popupOpen ? accent.soft(0.35)
                 : root.tint(dateArea.pressed ? 0.16 : dateArea.containsMouse ? 0.12 : 0.08)
            border.width: root.popupOpen ? 1 : 0
            border.color: Qt.rgba(accent.focusRing.r, accent.focusRing.g, accent.focusRing.b, 0.5)
            Behavior on color {
                enabled: motion.animate
                ColorAnimation { duration: motion.hover }
            }
        }

        Row {
            id: row
            anchors.verticalCenter: parent.verticalCenter
            LayoutMirroring.enabled: Application.layoutDirection === Qt.RightToLeft
            LayoutMirroring.childrenInherit: true

            // Padding 12; the dot cells carry 2 px of it themselves.
            Item {
                width: root.showDots ? root.pillPadding - dots.cellPadding : 0
                height: 1
            }

            WorkspaceDots {
                id: dots
                visible: root.showDots
                touch: m.touch
                motion: motion
                width: visible ? implicitWidth : 0
                anchors.verticalCenter: parent.verticalCenter
                cellHeight: pill.height
                count: root.desktopCount
                currentIndex: root.currentIndex
                names: desktopInfo.desktopNames
                activeColor: root.textColor
                inkColor: root.ink
                focusColor: root.focusColor
                location: Plasmoid.location
                onSwitchRequested: index => root.switchToDesktop(index)
                onOverviewRequested: root.showOverview()
            }

            // Date and time: one button that opens the calendar. It reaches the pill's edge so
            // the whole right part is clickable. The tooltip area is the outer item: a
            // hover-enabled item on top of a MouseArea would take the hover from it.
            PlasmaCore.ToolTipArea {
                id: dateTip

                readonly property real leading: root.showDots ? root.pillPadding - dots.cellPadding : root.pillPadding

                anchors.verticalCenter: parent.verticalCenter
                width: leading + timeRow.implicitWidth + root.pillPadding
                height: pill.height
                active: !root.popupOpen
                location: Plasmoid.location
                mainText: Qt.formatDate(clock.dateTime, Qt.locale(), Locale.LongFormat)
                subText: clock.isSystemTimeZone ? "" : clock.timeZoneName

                MouseArea {
                    id: dateArea
                    // The whole bar's height is the hit area (the drawn pill stays 24 or 32).
                    anchors.fill: parent
                    anchors.topMargin: root.vertical ? 0 : -Math.max(0, (root.height - pill.height) / 2)
                    anchors.bottomMargin: anchors.topMargin
                    hoverEnabled: true
                    activeFocusOnTab: true
                    acceptedButtons: Qt.LeftButton

                    Accessible.role: Accessible.ButtonDropDown
                    Accessible.name: dateLabel.visible ? dateLabel.text + ", " + timeLabel.text : timeLabel.text
                    Accessible.description: i18nc("@info:whatsthis", "Show the calendar")
                    Accessible.onPressAction: root.setPopupOpen(!root.popupOpen)

                    onContainsMouseChanged: if (containsMouse) root.prepareCalendar()
                    onPressed: {
                        root.prepareCalendar();
                        root.openOnPress = !root.popupOpen;
                    }
                    onClicked: root.setPopupOpen(root.openOnPress)
                    Keys.onPressed: event => {
                        if ([Qt.Key_Return, Qt.Key_Enter, Qt.Key_Space, Qt.Key_Select].indexOf(event.key) !== -1) {
                            root.setPopupOpen(!root.popupOpen);
                            event.accepted = true;
                        }
                    }

                    Row {
                        id: timeRow
                        x: dateTip.leading
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: root.pillPadding

                        FusionText {
                            id: dateLabel
                            anchors.verticalCenter: parent.verticalCenter
                            visible: Plasmoid.configuration.showDate && root.compactLevel < 2
                            metrics: m
                            px: 13
                            weight: 700
                            color: root.textColor
                            text: Qt.locale().toString(clock.dateTime, root.compactLevel >= 1
                                                       ? Formats.shortDateFormat(Qt.locale(), Qt.locale().dateFormat(Locale.ShortFormat))
                                                       : root.dateFormat)
                            font.features: { "tnum": 1 }
                        }

                        FusionText {
                            id: timeLabel
                            anchors.verticalCenter: parent.verticalCenter
                            width: root.timeBoxWidth
                            horizontalAlignment: Text.AlignHCenter
                            font.features: { "tnum": 1 }
                            metrics: m
                            display: true
                            px: 13
                            weight: 600
                            color: root.textColor
                            // CLDR puts a narrow no-break space before AM/PM ("2:49 PM"); Space
                            // Grotesk has no glyph for it, and a fallback font for one character
                            // would change the line's height. Its thin space looks the same.
                            text: root.timeText
                        }
                    }
                }
            }
        }

        // Touch: a pull-down of 24 px opens the calendar (TABLET 4.1 and 4.7). A layer above the
        // pill's mouse areas, so it sees the touch first; it holds only a passive grab until the
        // finger has moved 24 px, so taps still reach the pill.
        Item {
            anchors.fill: parent
            anchors.topMargin: root.vertical ? 0 : -Math.max(0, (root.height - pill.height) / 2)
            anchors.bottomMargin: anchors.topMargin
            z: 10
            DragHandler {
                acceptedDevices: PointerDevice.TouchScreen
                target: null
                xAxis.enabled: false
                dragThreshold: 24
                onActiveChanged: {
                    // (translation is still 0 when `active` turns true: use the press position)
                    const dy = centroid.position.y - centroid.pressPosition.y;
                    if (active) {
                        console.info("clockpill: pull-down gesture, dy " + Math.round(dy));
                        root.prepareCalendar();
                    }
                    if (active && dy > 0 && !root.popupOpen) {
                        console.info("clockpill: pull-down opens the calendar");
                        root.setPopupOpen(true);
                    }
                }
            }
        }

        // Keyboard focus on the date and time: ring around the whole pill.
        Rectangle {
            visible: dateArea.activeFocus
            anchors.fill: parent
            anchors.margins: -4
            radius: height / 2
            color: "transparent"
            border.width: 2
            border.color: root.focusColor
        }
    }

    // ---- Calendar pop-up
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
        visible: root.popupOpen && calendarLoader.status === Loader.Ready

        onVisibleChanged: {
            if (visible && calendarLoader.item) {
                calendarLoader.item.showToday();
                popup.requestActivate();
                calendarLoader.item.forceActiveFocus();
            } else if (!visible) {
                closeSync.restart();
            }
        }

        mainItem: Loader {
            id: calendarLoader
            active: root.calendarWanted
            asynchronous: true
            focus: true
            onLoaded: {
                item.showToday();
                item.forceActiveFocus();
            }
            sourceComponent: CalendarView {
                now: clock.dateTime
                firstDayOfWeek: Plasmoid.configuration.firstDayOfWeek
                touch: m.touch
                motion: motion
                dark: {
                    // The pop-up may use another colour set than the panel.
                    const c = Kirigami.Theme.backgroundColor;
                    return (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) < 0.5;
                }
                focus: true
                onCloseRequested: root.setPopupOpen(false)
            }
        }
        Connections {
            target: popup
            enabled: root.openStarted > 0
            function onFrameSwapped() {
                if (!popup.visible) {
                    return;
                }
                console.info("clockpill: calendar " + (root.calendarShown ? "open" : "first open") + ", first frame after "
                             + (Date.now() - root.openStarted) + " ms");
                root.openStarted = 0;
                root.calendarShown = true;
            }
        }
    }
}
