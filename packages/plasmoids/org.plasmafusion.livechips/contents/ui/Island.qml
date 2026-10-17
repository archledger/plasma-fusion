// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore

import "../code/chips.js" as Chips

// The island (board Island.dc.html, docs/parts/shell-livechips.md): while the top bar of this
// screen is hidden (the settings page's "Hide the top bar automatically"), what the chips would
// show sits at the top centre of the screen, after Apple's Dynamic Island: opaque black in light
// and dark, 4 px from the top. One thing shows compact, a leading part that names it and a
// trailing part with its state; a second one sits in a bubble beside it; a click opens the island
// in place (the app and what it uses with Mute, Stop sharing or End; a recording with Stop; the
// music with its controls); Esc, a click outside it or on its free part closes it. In a
// full-screen window only the privacy dots show.
//
// A window of Plasma's CriticalNotification type: KWin keeps the place it asks for and stacks it
// above full-screen windows (KWin 6.7.5 places an OnScreenDisplay window itself, two thirds down
// the screen). It takes no focus until it is opened, then it does (Esc). The black shape morphs
// between its sizes inside the window; the window keeps the larger size until a morph has ended,
// so it is not resized on every frame.
PlasmaCore.Dialog {
    id: island

    required property FusionMetrics metrics
    required property bool dark
    // The top bar of this screen is hidden ([General] barHidden, from the tablet KWin script).
    required property bool barHidden
    required property rect screenGeometry
    // Chips.island(): { mode, items, dots }
    required property var content
    // Chips.islandRows()
    required property var rows
    // { time } of Spectacle's recording, or null
    required property var recording
    // Keep awake's time left (Chips.timeLeft) while a timed Keep awake runs, else null
    required property var keepAwakeLeft
    // sources/Media.qml while its module is there, else null
    required property var media

    signal stopRecording()
    signal openKeepAwake()
    signal rowAction(var row)

    // The opened item ("privacy", "recording" or "music"), or "" while compact.
    property string opened: ""
    // The pointer on the full-screen dots: the compact island shows.
    property bool peek: false

    readonly property bool wanted: barHidden && content.mode !== "none"
    readonly property string mode: content.mode === "dots" && !peek && opened === "" ? "dots" : opened !== "" ? "opened" : "compact"
    readonly property var items: content.mode === "dots" ? ["privacy"] : content.items
    readonly property bool bubbleShown: mode === "compact" && items.length > 1

    function open(item: string): void {
        if (item === "keepawake") {
            openKeepAwake();
        } else if (item !== "") {
            opened = item;
        }
    }
    function close(): void {
        opened = "";
        peek = false;
    }
    // The pointer's peek at the dots ends with the dots (else a later full screen kept it).
    readonly property string contentMode: content.mode
    onContentModeChanged: if (contentMode !== "dots") peek = false
    // An item that is no longer there closes; nothing to show closes it all.
    onItemsChanged: {
        if (opened !== "" && items.indexOf(opened) < 0) {
            close();
        }
        report.restart();
    }
    onWantedChanged: if (!wanted) close()

    // ---- sizes (board: compact 32 px high, at least 132 wide, 6 px margins; the bubble 32 px, 6
    // px beside it; opened 400 px wide, radius 28, 14 px margins; full screen 14 px, 6 px dots)
    readonly property real compactHeight: metrics.px(32)
    // The opened island stays on the screen (4 px from its top, 24 px above its bottom); its rows
    // scroll inside (IslandOpened.qml).
    readonly property real maxHeight: Math.max(metrics.px(120), screenGeometry.height - 4 - metrics.px(24))
    // Opened: 400 px wide, at most the screen's width less 8 px on each side.
    readonly property real openedWidth: Math.max(metrics.px(200), Math.min(metrics.px(400), screenGeometry.width - metrics.px(16)))
    readonly property real gap: metrics.px(6)
    readonly property real targetWidth: mode === "dots" ? dotsRow.implicitWidth + metrics.px(8)
        : mode === "opened" ? openedWidth
        : Math.max(metrics.px(132), leading.implicitWidth + trailing.implicitWidth + metrics.px(28) + 2 * metrics.px(6))
    readonly property real targetHeight: mode === "dots" ? metrics.px(14)
        : mode === "opened" ? openedContent.implicitHeight + 2 * metrics.px(14) : compactHeight
    readonly property real targetRadius: mode === "dots" ? metrics.px(7) : mode === "opened" ? metrics.px(28) : compactHeight / 2

    // The window: the shape's largest size during a morph, room for the bubble on both sides (so
    // the island stays centred on the screen).
    property real frameWidth: targetWidth
    property real frameHeight: targetHeight
    readonly property real side: bubbleShown ? gap + compactHeight : 0
    function grow(): void {
        frameWidth = Math.max(frameWidth, targetWidth);
        frameHeight = Math.max(frameHeight, targetHeight);
        settle.restart();
    }
    onTargetWidthChanged: grow()
    onTargetHeightChanged: grow()

    // Shown: faded in when the bar has slid away, out as it slides in.
    property real shown: wanted ? 1 : 0
    Behavior on shown {
        enabled: motionTokens.animate
        NumberAnimation { duration: island.wanted ? motionTokens.popupIn : motionTokens.popupOut; easing.type: motionTokens.standardEasing }
    }

    type: PlasmaCore.Dialog.CriticalNotification
    // No visual parent: libplasma 6.7.5 makes a Dialog the transient of its visual parent's window,
    // and plasmashell keeps an auto-hide panel shown while a window it is the transient parent of
    // is visible (PanelView::restoreAutoHide); the island is not the bar's pop-up.
    location: PlasmaCore.Types.Floating
    backgroundHints: PlasmaCore.Dialog.NoBackground
    // Focus only while opened: Esc, and a click elsewhere deactivates it. Taken once the window has
    // its opened size (focusWanted, after the morph): KWin activates the window and configures it
    // with the size it has then, and Qt takes that size, so a window still at its compact size
    // would stay so. No WindowStaysOnTopHint: libplasma 6.7.5 makes a Dialog with it a Dock (a
    // panel whose windows go below, DialogPrivate::applyType), under full-screen windows; a critical
    // notification is above them.
    property bool focusWanted: false
    flags: focusWanted ? 0 : Qt.WindowDoesNotAcceptFocus
    visible: wanted || shown > 0
    x: screenGeometry.x + Math.round((screenGeometry.width - frame.width) / 2)
    y: screenGeometry.y + 4
    // The frame's size and the window's place, bound again when the focus changes: the Dialog sizes
    // its main item to the window whenever the window is resized from outside (a change of flags
    // can give the window the platform's last size back), and in Qt 6 that resize ends the main
    // item's size bindings; the window's place follows the frame's width.
    function fit(): void {
        frame.width = Qt.binding(() => island.frameWidth + 2 * island.side);
        frame.height = Qt.binding(() => island.frameHeight);
        x = Qt.binding(() => screenGeometry.x + Math.round((screenGeometry.width - frame.width) / 2));
        y = Qt.binding(() => screenGeometry.y + 4);
    }

    property bool wasActive: false
    onActiveChanged: {
        if (active) {
            wasActive = true;
        } else if (wasActive) {
            wasActive = false;
            close();
        }
    }
    onOpenedChanged: {
        if (opened !== "") {
            takeFocus.restart();
        } else {
            takeFocus.stop();
            focusWanted = false;
        }
        report.restart();
    }
    onFocusWantedChanged: {
        fit();
        Qt.callLater(island.fit);
        if (focusWanted) {
            Qt.callLater(() => { island.requestActivate(); openedContent.forceActiveFocus(); });
        }
    }

    onVisibleChanged: report.restart()
    onModeChanged: report.restart()

    // ---- the parts
    function glyphColor(kind: string): color {
        return Chips.ISLAND_COLOURS[kind] || "#ffffff";
    }
    // The key line: over dark windows, 1 px in the leading part's colour (Apple's key line).
    readonly property color keyLine: {
        const kind = items[0] === "privacy" ? (content.dots[0] || "") : items[0] === "recording" ? "recording" : "";
        const c = items[0] === "music" ? Qt.color("#f2a65a") : Qt.color(kind !== "" ? glyphColor(kind) : "#ffffff");
        return Qt.rgba(c.r, c.g, c.b, kind !== "" || items[0] === "music" ? 0.45 : 0.18);
    }
    function leftText(left: var): string {
        if (!left) {
            return "";
        }
        if (left.hours > 0) {
            return left.minutes > 0 ? i18nc("@info time left of Keep awake, in the bar", "%1 h %2 min", left.hours, left.minutes)
                                    : i18nc("@info time left of Keep awake, in the bar", "%1 h", left.hours);
        }
        return i18nc("@info time left of Keep awake, in the bar", "%1 min", left.minutes);
    }
    function kindsText(kinds: var): string {
        const names = {
            camera: i18nc("@info used by an app", "camera"), microphone: i18nc("@info used by an app", "microphone"),
            screen: i18nc("@info used by an app", "screen sharing"), remote: i18nc("@info used by an app", "remote control"),
            ssh: i18nc("@info used by an app", "signed in over SSH")
        };
        const list = kinds.map(k => names[k] || k);
        const text = list.length === 1 ? list[0] : list.length === 2 ? i18nc("@info two things in use", "%1 and %2", list[0], list[1])
            : i18nc("@info three or more things in use, the last one apart", "%1 and %2", list.slice(0, -1).join(", "), list[list.length - 1]);
        return text.charAt(0).toUpperCase() + text.slice(1);
    }

    mainItem: Item {
        id: frame
        width: island.frameWidth + 2 * island.side
        height: island.frameHeight
        opacity: island.shown

        // The non-visual parts (a Dialog's children are its main item).
        // Debug output for tests: QT_LOGGING_RULES="org.plasmafusion.livechips.debug=true".
        LoggingCategory {
            id: log
            name: "org.plasmafusion.livechips"
            defaultLogLevel: LoggingCategory.Warning
        }

        Motion {
            id: motionTokens
        }

        // The focus, once the window has its opened size.
        Timer {
            id: takeFocus
            interval: Math.max(motionTokens.surface, 1) + 150
            onTriggered: island.focusWanted = island.opened !== ""
        }
        Timer {
            id: settle
            interval: Math.max(motionTokens.surface, 1) + 50
            onTriggered: {
                island.frameWidth = island.targetWidth;
                island.frameHeight = island.targetHeight;
                report.restart();
            }
        }

        // Test hook: the island's shape and bubble on the screen, once a morph has ended.
        Timer {
            id: report
            interval: 300
            onTriggered: {
                if (!island.visible) {
                    console.debug(log, "livechips: island none");
                    return;
                }
                const w = "; window " + Math.round(island.x) + "," + Math.round(island.y) + " " + Math.round(island.width) + "x" + Math.round(island.height);
                const g = body.mapToGlobal(0, 0);
                const b = bubble.mapToGlobal(0, 0);
                console.debug(log, "livechips: island " + island.mode + " " + island.items.join(",") + (island.opened !== "" ? " opened " + island.opened : "")
                              + " at " + Math.round(g.x) + "," + Math.round(g.y) + " " + Math.round(body.width) + "x" + Math.round(body.height)
                              + (island.bubbleShown ? "; bubble " + Math.round(b.x) + "," + Math.round(b.y) + " " + Math.round(bubble.width) + "x" + Math.round(bubble.height) : "") + w);
            }
        }

        // The island: one black shape for every size.
        Rectangle {
            id: body
            x: island.side + (island.frameWidth - width) / 2
            width: island.targetWidth
            height: island.targetHeight
            radius: island.targetRadius
            color: "#000000"
            border.width: island.dark ? 1 : 0
            border.color: island.keyLine
            clip: true
            Behavior on width {
                enabled: island.motion.animate
                NumberAnimation { duration: island.motion.surface; easing.type: island.motion.standardEasing }
            }
            Behavior on height {
                enabled: island.motion.animate
                NumberAnimation { duration: island.motion.surface; easing.type: island.motion.standardEasing }
            }
            Behavior on radius {
                enabled: island.motion.animate
                NumberAnimation { duration: island.motion.surface; easing.type: island.motion.standardEasing }
            }

            Accessible.role: Accessible.Button
            Accessible.name: island.opened !== "" ? i18nc("@action:button the island at the top of the screen", "Close the island")
                                                   : i18nc("@action:button the island at the top of the screen", "Open the island")
            Accessible.onPressAction: island.opened !== "" ? island.close() : island.open(island.items[0] || "")

            // A click on the island opens it; on an opened island's free part, closes it.
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onClicked: island.opened !== "" ? island.close() : island.open(island.items[0] || "")
                onContainsMouseChanged: if (island.content.mode === "dots") island.peek = containsMouse || island.opened !== ""
            }

            // ---- full screen: the privacy dots
            Row {
                id: dotsRow
                anchors.centerIn: parent
                spacing: island.metrics.px(4)
                visible: island.mode === "dots"
                Repeater {
                    model: island.content.dots
                    delegate: Rectangle {
                        required property string modelData
                        width: island.metrics.px(6)
                        height: width
                        radius: width / 2
                        color: island.glyphColor(modelData)
                    }
                }
            }

            // ---- compact: leading and trailing parts
            IslandPart {
                id: leading
                island: island
                item: island.items[0] || ""
                leading: true
                anchors.left: parent.left
                anchors.leftMargin: island.metrics.px(6)
                anchors.verticalCenter: parent.top
                anchors.verticalCenterOffset: island.compactHeight / 2
                visible: island.mode === "compact"
            }
            IslandPart {
                id: trailing
                island: island
                item: island.items[0] || ""
                leading: false
                anchors.right: parent.right
                anchors.rightMargin: island.metrics.px(10)
                anchors.verticalCenter: parent.top
                anchors.verticalCenterOffset: island.compactHeight / 2
                visible: island.mode === "compact"
            }

            // ---- opened
            IslandOpened {
                id: openedContent
                island: island
                x: island.metrics.px(14)
                y: island.metrics.px(14)
                width: island.openedWidth - 2 * island.metrics.px(14)
                visible: island.mode === "opened"
                opacity: visible ? 1 : 0
                Behavior on opacity {
                    enabled: island.motion.animate
                    NumberAnimation { duration: island.motion.popupIn; easing.type: island.motion.standardEasing }
                }
                Keys.onEscapePressed: island.close()
            }
        }

        // The second thing, detached in a bubble beside the island.
        Rectangle {
            id: bubble
            x: body.x + body.width + island.gap
            width: island.compactHeight
            height: island.compactHeight
            radius: height / 2
            color: "#000000"
            border.width: island.dark ? 1 : 0
            border.color: island.keyLine
            visible: island.bubbleShown
            Accessible.role: Accessible.Button
            Accessible.name: island.items[1] === "keepawake" ? i18nc("@action:button", "Keep awake")
                : island.items[1] === "music" ? i18nc("@action:button the music playing", "Music")
                : i18nc("@action:button", "Recording")
            Accessible.onPressAction: island.open(island.items[1] || "")

            IslandPart {
                anchors.centerIn: parent
                island: island
                item: island.items[1] || ""
                leading: true
            }
            MouseArea {
                anchors.fill: parent
                onClicked: island.open(island.items[1] || "")
            }
        }
    }

    // The motion tokens, for the parts.
    readonly property alias motion: motionTokens
}
