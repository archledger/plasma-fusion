/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes

// One app in the dock: its tile (the Fusion icon, or any other icon on a neutral Fusion tile,
// FusionIconTile) over a soft drop shadow, the running dot or active pill under it, an unread
// count or progress ring (Unity LauncherEntry, GAPS G17), an audio indicator while the app plays
// sound or is muted (a click on it mutes or unmutes the app) and, when the app asks for attention,
// one short bounce next to the orange dot (G26). Calendar apps show today's date on their tile.
//
// The item keeps its rest size (`iconSize`) and rest position. Magnification never changes a
// size: the dock sets `grow` (extra px of the magnified icon) and `shift` (horizontal offset),
// the icon box scales around its bottom centre and the whole item is translated. So nothing is
// laid out, re-rasterised or re-blurred while the pointer moves (EFFECTS.md section 4).
Item {
    id: task

    required property int index
    required property var model
    required property DockPalette pal
    required property Motion motion

    property real iconSize: 48
    property int bottomPad: 14
    // Tablet posture: bigger dot and pill, 4 px under the icon (TABLET 4.4).
    property bool tablet: false
    // Magnification of this frame, set by the dock.
    property real grow: 0
    property real shift: 0
    // Size of the crisp magnified icon; it is loaded once the dock was first hovered.
    property int zoomSize: 62
    property bool zoomReady: false
    // Start-up pulse cycles (3, or fewer on battery: the dock's powerTier).
    property int pulseCycles: 3
    // The dock's gap between icons (12 in tablet posture, 8 on the laptop).
    property real gap: 8
    // Unity LauncherEntry state of this app ({count, countVisible, progress, progressVisible,
    // urgent}) or null.
    property var entry: null
    // Today, for the calendar tile ("SEP", "28").
    property string monthText: ""
    property string dayText: ""

    readonly property bool isLauncher: model.IsLauncher === true
    readonly property bool isStartup: model.IsStartup === true
    readonly property bool isRunning: !isLauncher && !isStartup
    readonly property bool isActive: model.IsActive === true
    readonly property bool demandsAttention: model.IsDemandingAttention === true || (entry !== null && entry.urgent === true)
    // Launchers of apps that are not installed have no AppId; they are not shown.
    readonly property bool resolvable: !isLauncher || (model.AppId ?? "") !== ""
    readonly property string name: model.AppName || model.display || ""
    // The theme icon's name: apps name their icon after their desktop id, which is AppId (without
    // the ".desktop" some entries carry).
    readonly property string iconName: String(model.AppId ?? "").replace(/\.desktop$/, "")
    readonly property bool calendarApp: ["korganizer", "org.kde.korganizer", "office-calendar", "gnome-calendar",
                                         "org.kde.merkuro.calendar", "org.kde.kalendar",
                                         "kalendar"].indexOf(iconName) !== -1
    // Today's date goes over the designed calendar tile only: not over an app's own icon (a foreign
    // one, or a familiar app icon; KOrganizer keeps its designed tile in both modes).
    readonly property bool calendarTile: calendarApp && !restTile.foreign && !restTile.familiar
    // The app's notifications not seen yet (the dock's count, see main.qml); the badge shows the
    // larger of it and the app's own Unity count.
    property int notificationCount: 0
    readonly property int unityCount: entry !== null && entry.countVisible === true ? Math.max(0, Math.round(entry.count || 0)) : 0
    readonly property int badgeCount: Math.max(unityCount, notificationCount)
    readonly property real progress: entry !== null && entry.progressVisible === true ? Math.max(0, Math.min(1, entry.progress || 0)) : -1

    // Audio (AudioStreams.qml; null without plasma-pa): the app's streams. As in the stock task
    // manager, the indicator shows a playing app after 2 s (no flash for short sounds) and a
    // muted one at once.
    property QtObject audio: null
    property var audioStreams: []
    readonly property bool playingAudio: audioStreams.some(s => !s.corked)
    readonly property bool muted: audioStreams.length > 0 && audioStreams.every(s => s.muted)
    readonly property bool audioShown: muted || (playingAudio && audioDelay.passed)
    readonly property int appPid: model.AppPid ?? 0
    function updateAudioStreams(): void {
        audioStreams = audio && isRunning ? audio.streamsFor(iconName, appPid, String(model.AppName ?? "")) : [];
    }
    // Mutes every stream of the app, or unmutes them all when all are muted.
    function toggleMuted(): void {
        const on = !muted;
        for (const s of audioStreams) {
            s.setMuted(on);
        }
    }
    function hitsAudioBadge(x: real, y: real): bool {
        const p = audioBadge.mapFromItem(mouse, x, y);
        return audioShown && p.x >= -4 && p.y >= -4 && p.x <= audioBadge.width + 4 && p.y <= audioBadge.height + 4;
    }
    onAudioChanged: updateAudioStreams()
    onAppPidChanged: updateAudioStreams()
    onIsRunningChanged: updateAudioStreams()
    onPlayingAudioChanged: if (!playingAudio) audioDelay.passed = false
    Connections {
        target: task.audio
        function onStreamsChanged(): void {
            task.updateAudioStreams();
        }
    }
    Timer {
        id: audioDelay
        property bool passed: false
        interval: 2000
        running: task.playingAudio && !passed
        onTriggered: passed = true
    }
    // Set by the dock, which knows from its magnification which icon is under the pointer; the
    // item's own MouseArea does not track hover (one hover pass per pointer event for the whole
    // dock instead of one per item).
    property bool hovered: false
    readonly property alias pressed: mouse.pressed
    readonly property alias mouseArea: mouse
    readonly property alias iconItem: iconBox
    readonly property alias audioBadge: audioBadge
    readonly property real iconTop: iconBox.y
    readonly property real magnification: (iconSize + grow) / iconSize

    signal activated(int modifiers)
    signal newInstanceRequested()
    signal menuRequested()
    signal dragMoved(real sceneX)
    signal dragFinished()
    // A drag upwards (48 px) with a mouse, touchpad or pen: the dock drags the app's launcher,
    // for a desktop shortcut (BACKLOG M3); false when the drag ends.
    signal desktopDrag(bool active)
    // Tablet posture: the icon dragged up out of the dock to split the screen (SPLIT.md item 1),
    // with the finger in global coordinates.
    signal splitDragMoved(point globalPos)
    signal splitDragFinished(bool cancelled)
    // Held still for 300 ms (tablet posture): the icon lifts and a drag up starts a split; the
    // dock's swipe-up (the launcher) steps aside meanwhile.
    signal splitArmed(bool armed)

    // shown: false for a row the dock leaves out (tablet recents beyond the limit, TABLET2 N2)
    property bool shown: true
    visible: resolvable && shown
    width: Math.round(iconSize)
    activeFocusOnTab: visible
    transform: Translate { x: task.shift; y: -bounce.lift }

    Accessible.role: Accessible.Button
    Accessible.name: task.badgeCount > 0 ? i18ncp("@info:tooltip app name and its unread count", "%2, %1 unread", "%2, %1 unread", task.badgeCount, name) : name
    Accessible.description: isLauncher ? i18nc("@info:tooltip", "Pinned, not running")
                                       : (demandsAttention ? i18nc("@info:tooltip", "Needs attention")
                                                           : (isActive ? i18nc("@info:tooltip", "Active") : i18nc("@info:tooltip", "Running")))
    Accessible.onPressAction: task.activated(0)

    Keys.onPressed: event => {
        switch (event.key) {
        case Qt.Key_Space:
        case Qt.Key_Enter:
        case Qt.Key_Return:
        case Qt.Key_Select:
            task.activated(event.modifiers);
            event.accepted = true;
            break;
        case Qt.Key_Menu:
            task.menuRequested();
            event.accepted = true;
            break;
        }
    }

    // The icon at rest size; scaled (never resized) while magnified.
    Item {
        id: iconBox
        width: Math.round(task.iconSize)
        height: width
        anchors.horizontalCenter: parent.horizontalCenter
        y: task.height - task.bottomPad - height
        // Press feedback: 0.94 and 80 % opacity (TABLET 4.4).
        readonly property bool held: mouse.pressed && !mouse.dragging && !mouse.armed
        // lifted while armed for a split drag (iPadOS: the icon rises before it can be dragged)
        property real pressScale: mouse.armed ? 1.12 : held ? 0.94 : 1
        Behavior on pressScale {
            enabled: task.motion.animate
            NumberAnimation { duration: task.motion.pressScale; easing.type: task.motion.standardEasing }
        }
        opacity: task.isStartup ? startupPulse.value : (held ? 0.8 : 1)
        transform: Scale {
            origin.x: iconBox.width / 2
            origin.y: iconBox.height
            xScale: task.magnification * iconBox.pressScale
            yScale: task.magnification * iconBox.pressScale
        }

        // filter: drop-shadow(0 3px 6px rgba(0,0,0,.35)) in the boards, under the tile shape (the
        // Fusion tiles and the neutral tile share radius 0.234 x size): one signed-distance
        // shader, no layer and no blur pass per item.
        FusionShadow {
            anchors.fill: parent
            radius: 0.234 * width
            offset.y: 3
            blur: 6
            spread: -1
            color: task.pal.iconShadow
        }

        // The crisp tile on top: at rest size, or at the magnified size while magnified (so a
        // scaled-up texture is never shown).
        FusionIconTile {
            id: restTile
            anchors.fill: parent
            size: iconBox.width
            source: task.model.decoration
            iconName: task.iconName
            visible: !zoomLoader.item || task.grow <= 0.5
        }

        Loader {
            id: zoomLoader
            active: task.zoomReady && task.zoomSize > task.iconSize
            asynchronous: true
            anchors.centerIn: parent
            sourceComponent: FusionIconTile {
                width: task.zoomSize
                height: task.zoomSize
                size: task.zoomSize
                scale: task.iconSize / task.zoomSize
                source: task.model.decoration
                iconName: task.iconName
                visible: task.grow > 0.5
            }
        }

        // Calendar apps: today's month and day over the tile's fixed "SEP" / "28" (AppIcon board,
        // 64-unit tile: red band 0-21 with the month, the day in 21-60). The app list is names.py
        // APPS['calendar'] (the names that draw this art) and the patch paints the art's own
        // colours, so it hides the labels without a seam; tools/checks/calendar-tile.py keeps both
        // in step.
        Item {
            id: calOverlay
            anchors.fill: parent
            visible: task.calendarTile && task.dayText !== ""
            readonly property real u: width / 64

            Rectangle {
                x: 14 * calOverlay.u
                y: 3 * calOverlay.u
                width: 36 * calOverlay.u
                height: 16 * calOverlay.u
                color: "#e5484d"
                Text {
                    anchors.centerIn: parent
                    text: task.monthText
                    color: "#ffffff"
                    font.pixelSize: 9 * calOverlay.u
                    font.weight: Font.ExtraBold
                    textFormat: Text.PlainText
                }
            }
            Rectangle {
                x: 10 * calOverlay.u
                y: 23 * calOverlay.u
                width: 44 * calOverlay.u
                height: 35 * calOverlay.u
                color: "#f6f4ef"
                Text {
                    anchors.centerIn: parent
                    text: task.dayText
                    color: "#1b2031"
                    font.pixelSize: 26 * calOverlay.u
                    font.weight: Font.ExtraBold
                    font.features: { "tnum": 1 }
                    textFormat: Text.PlainText
                }
            }
        }

        // Unread count: the Controls board's badge (20 px, radius 10, accent, 11 px 800), at the
        // tile's top-right corner.
        Rectangle {
            visible: task.badgeCount > 0
            x: parent.width - width + 6
            y: -6
            height: 20
            width: Math.max(20, countText.implicitWidth + 12)
            radius: 10
            color: task.pal.accentFill
            Text {
                id: countText
                anchors.centerIn: parent
                text: task.badgeCount > 99 ? "99+" : String(task.badgeCount)
                color: task.pal.accentText
                font.pixelSize: 11
                font.weight: Font.ExtraBold
                font.features: { "tnum": 1 }
                textFormat: Text.PlainText
            }
        }

        // Audio: a playing or muted app, on the progress ring's disc in the icon's top-left corner
        // (the count and progress use the right one). A click on it mutes or unmutes (the
        // MouseArea). Inside the icon, not over its edge like the count: the dock tracks the
        // pointer only up to 10 px above the resting icons, and a magnified icon rises past that;
        // here the disc's centre stays below it at every magnified size (48-72 px).
        Rectangle {
            id: audioBadge
            x: 2
            y: 2
            width: 20
            height: 20
            radius: 10
            color: task.pal.progressDisc
            opacity: task.audioShown ? 1 : 0
            visible: opacity > 0
            Behavior on opacity {
                enabled: task.motion.animate
                NumberAnimation { duration: task.motion.toggle }
            }
            Accessible.role: Accessible.Button
            Accessible.checkable: true
            Accessible.checked: task.muted
            Accessible.name: task.muted ? i18nc("@action:button", "Unmute %1", task.name) : i18nc("@action:button", "Mute %1", task.name)
            Accessible.onPressAction: task.toggleMuted()
            Glyph {
                anchors.centerIn: parent
                size: 14
                // Quick settings' speaker glyphs (Icons.js speaker + wave1 / muteCross).
                path: task.muted ? "M4 9h4l5-4v14l-5-4H4zM16 9l5 6M21 9l-5 6" : "M4 9h4l5-4v14l-5-4H4zM16 9a4 4 0 0 1 0 6"
                color: task.pal.ink
            }
        }

        // Progress (a download, a copy): a ring on a small disc at the top-right corner (next to
        // no count: the count wins).
        Item {
            visible: task.progress >= 0 && task.badgeCount === 0
            x: parent.width - width + 6
            y: -6
            width: 20
            height: 20
            Rectangle {
                anchors.fill: parent
                radius: 10
                color: task.pal.progressDisc
            }
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: task.pal.accentFill
                    strokeWidth: 3
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    PathAngleArc {
                        centerX: 10
                        centerY: 10
                        radiusX: 6.5
                        radiusY: 6.5
                        startAngle: -90
                        sweepAngle: 360 * Math.max(0.01, task.progress)
                    }
                }
            }
        }
    }

    // Launch feedback: the icon pulses until the app's window appears, at most three times
    // (fewer on battery).
    QtObject {
        id: startupPulse
        property real value: 1
    }

    SequentialAnimation {
        id: pulseAnimation
        loops: task.motion.loops(task.pulseCycles)
        onStopped: startupPulse.value = 1
        NumberAnimation { target: startupPulse; property: "value"; to: 0.45; duration: task.motion.pulse; easing.type: Easing.InOutSine }
        NumberAnimation { target: startupPulse; property: "value"; to: 1; duration: task.motion.pulse; easing.type: Easing.InOutSine }
    }

    // Restarted on every launch (a binding on `running` would be dropped when the animation
    // stops itself); no pulse with animations turned off or at the critical battery tier.
    function updatePulse(): void {
        if (isStartup && task.motion.animate && task.pulseCycles > 0) {
            pulseAnimation.restart();
        } else {
            pulseAnimation.stop();
            startupPulse.value = 1;
        }
    }
    onIsStartupChanged: updatePulse()
    Component.onCompleted: updatePulse()

    // Needs attention: one short bounce (the dot alone is a colour-only cue, GAPS G26).
    QtObject {
        id: bounce
        property real lift: 0
    }
    SequentialAnimation {
        id: bounceAnimation
        NumberAnimation { target: bounce; property: "lift"; to: 10; duration: task.motion.popupIn; easing.type: Easing.OutCubic }
        NumberAnimation { target: bounce; property: "lift"; to: 0; duration: task.motion.surface; easing.type: Easing.OutBounce }
    }
    onDemandsAttentionChanged: {
        if (demandsAttention && task.motion.animate) {
            bounceAnimation.restart();
        }
    }

    // Keyboard focus ring around the icon.
    Rectangle {
        anchors.fill: iconBox
        anchors.margins: -4
        radius: Math.round(iconBox.width * 0.27) + 4
        color: "transparent"
        border.width: 2
        border.color: task.pal.focusRing
        visible: task.activeFocus
        antialiasing: true
    }

    // Running indicator under the icon: 5 x 4 dot or 16 x 4 pill 5 px below it (6 x 4 / 18 x 4,
    // 4 px, in tablet posture).
    Rectangle {
        id: indicator
        anchors.horizontalCenter: parent.horizontalCenter
        y: task.height - task.bottomPad + (task.tablet ? 4 : 5)
        height: 4
        radius: 2
        width: task.isActive ? (task.tablet ? 18 : 16) : (task.tablet ? 6 : 5)
        color: task.isActive ? task.pal.activePill : (task.demandsAttention ? task.pal.attention : task.pal.runningDot)
        visible: task.isRunning || task.isStartup
        opacity: task.isStartup ? startupPulse.value : 1

        Behavior on width {
            enabled: task.motion.animate
            NumberAnimation { duration: task.motion.toggle; easing.type: task.motion.standardEasing }
        }
    }

    MouseArea {
        id: mouse

        property point pressPoint
        property bool dragging: false
        property bool splitting: false
        property bool armed: false
        property bool suppressClick: false
        onArmedChanged: task.splitArmed(armed)
        function disarm() {
            holdArm.stop();
            armed = false;
        }
        Timer {
            id: holdArm
            interval: 300
            onTriggered: {
                if (mouse.pressed && !mouse.dragging && task.tablet) {
                    mouse.armed = true;
                }
            }
        }

        // Reach into the gaps next to the icon so that the pointer is always over one item: the
        // rest size plus half the gap on each side, widened by the icon's growth so that the
        // magnified neighbours never leave a gap without an item between them.
        // (half the gap on each side: a long press in a gap reached the panel, which then went into
        // its edit mode, in tablet posture where the gap is 12 px)
        x: -task.gap / 2 - task.grow / 2
        y: iconBox.y - 10 - task.grow
        width: parent.width + task.gap + task.grow
        height: parent.height - y
        hoverEnabled: false
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        // A long press opens the menu (touch, TABLET 4.4; also the mouse); in tablet posture a
        // little later, so that a drag can start after the 300 ms lift.
        pressAndHoldInterval: task.tablet ? 650 : 500

        onPressed: mouse => {
            pressPoint = Qt.point(mouse.x, mouse.y);
            dragging = false;
            splitting = false;
            suppressClick = false;
            disarm();
            if (task.tablet && mouse.button === Qt.LeftButton) {
                holdArm.restart();
            }
        }
        onPressAndHold: mouse => {
            if (!dragging && !splitting && mouse.button === Qt.LeftButton) {
                suppressClick = true;
                task.menuRequested();
            }
        }
        onPositionChanged: mouse => {
            if (!(mouse.buttons & Qt.LeftButton)) {
                return;
            }
            const dx = mouse.x - pressPoint.x;
            const dy = mouse.y - pressPoint.y;
            // moved before the lift: a swipe or a reorder, not a split
            if (!armed && Math.hypot(dx, dy) > 10) {
                holdArm.stop();
            }
            // Tablet posture, after the lift: decided after 24 px, upwards (up to ~63 degrees off
            // vertical) a split drag, mostly sideways a reorder.
            if (armed && !dragging && !splitting) {
                if (Math.hypot(dx, dy) < 24) {
                    return;
                }
                if (dy < 0 && -dy >= Math.abs(dx) * 0.5) {
                    splitting = true;
                    suppressClick = true;
                } else {
                    dragging = true;
                }
            }
            if (splitting) {
                task.splitDragMoved(mapToGlobal(mouse.x, mouse.y));
                return;
            }
            if (!dragging && !armed && Math.abs(dx) > Qt.styleHints.startDragDistance
                    && !(task.tablet && dy < 0 && Math.abs(dy) > Math.abs(dx))) {
                dragging = true;
            }
            if (dragging) {
                task.dragMoved(mapToItem(null, mouse.x, mouse.y).x);
            }
        }
        onReleased: mouse => {
            disarm();
            if (splitting) {
                splitting = false;
                suppressClick = true;
                task.splitDragFinished(false);
                return;
            }
            if (dragging) {
                dragging = false;
                suppressClick = true;
                task.dragFinished();
            }
        }
        onCanceled: {
            disarm();
            if (splitting) {
                splitting = false;
                task.splitDragFinished(true);
            }
            if (dragging) {
                dragging = false;
                task.dragFinished();
            }
        }
        // Upwards: a drag of the launcher (Kickoff's way, a pointer handler that takes the point
        // from this mouse area once it has moved 48 px up; sideways stays the reorder above).
        DragHandler {
            // (tablet posture: an upward drag splits the screen instead)
            enabled: !task.tablet
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad | PointerDevice.Stylus
            target: null
            xAxis.enabled: false
            dragThreshold: 48
            onActiveChanged: {
                if (active) {
                    mouse.suppressClick = true;
                }
                task.desktopDrag(active);
            }
        }

        onClicked: mouse => {
            if (suppressClick) {
                suppressClick = false;
                return;
            }
            if (mouse.button === Qt.RightButton) {
                task.menuRequested();
            } else if (mouse.button === Qt.MiddleButton) {
                task.newInstanceRequested();
            } else if (task.hitsAudioBadge(mouse.x, mouse.y)) {
                task.toggleMuted();
            } else {
                task.activated(mouse.modifiers);
            }
        }
    }
}
