// SPDX-FileCopyrightText: 2015 Marco Martin <notmart@gmail.com>
// SPDX-FileCopyrightText: 2021-2023 Devin Lin <devin@kde.org>
// SPDX-FileCopyrightText: 2024-2025 Luis Büchi <luis.buechi@kdemail.net>
// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T

import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents
import org.kde.kwin 3.0 as KWinComponents

Item {
    id: delegate

    required property var taskSwitcher
    property var taskSwitcherHelpers: taskSwitcher.taskSwitcherHelpers

    required property QtObject window

    required property var model

    required property real previewHeight
    required property real previewWidth

    readonly property real dragOffset: -control.y

    readonly property int currentIndex: model.index

    // whether this task is being interacted with
    readonly property bool interactingActive: control.pressed && control.passedDragThreshold

    // whether to show the text header
    property bool showHeader: true

    // the amount to darken the task preview by
    property real darken: 0

    opacity: 1 - dragOffset / taskSwitcher.height

//BEGIN functions
    function closeApp(): void {
        delegate.window.closeWindow();
    }

    function activateApp(): void {
        const w = delegate.window;
        if (w.tile) {
            // Plasma Fusion: an app in a split keeps its half, and the app in the other half comes
            // up with it (owner's screencast 2026-10-02: picking one half maximized it).
            const partner = splitPartner(w);
            if (partner) {
                KWinComponents.Workspace.activeWindow = partner;
            }
        } else {
            // Plasma Fusion: apps run maximized in tablet posture (Plasma Mobile without convergence mode).
            w.setMaximize(true, true);
        }
        delegate.taskSwitcherHelpers.openApp(model.index);
    }

    // The topmost visible window tiled on the other side of the same screen (the tablet script's
    // split divider pairs them the same way).
    function splitPartner(w): var {
        const g = w.tile.relativeGeometry;
        const left = g.x < 0.01 && g.width < 0.99;
        const order = KWinComponents.Workspace.stackingOrder;
        for (let i = order.length - 1; i >= 0; --i) {
            const o = order[i];
            if (o === w || o.deleted || !o.normalWindow || o.minimized || o.output !== w.output || !o.tile) {
                continue;
            }
            const og = o.tile.relativeGeometry;
            if (og.height > 0.99 && (left ? og.x > 0.01 && og.x + og.width > 0.99 : og.x < 0.01 && og.width < 0.99)) {
                return o;
            }
        }
        return null;
    }

    function minimizeApp(): void {
        delegate.window.minimized = true;
    }
//END functions

    MouseArea {
        id: control
        width: delegate.width
        height: delegate.height
        Accessible.role: Accessible.Button
        Accessible.name: i18n("Open %1", delegate.window.caption)

        // set cursor shape here, since taphandler seems to not be able to do it
        cursorShape: Qt.PointingHandCursor

        property bool movingUp: false
        property real oldY: y
        onYChanged: {
            movingUp = y < oldY;
            oldY = y;
        }

        onClicked: {
            if (!passedDragThreshold) {
                delegate.activateApp();
            }
        }

        // pixels before we start treating it as drag event
        readonly property real dragThreshold: 5

        property real startPosition: 0
        property bool hasStartPosition: false
        property bool passedDragThreshold: false

        onPositionChanged: (mouse) => {
            // map it to the root area, so that it doesn't jitter (since this item is moving)
            const yPos = control.mapToItem(delegate, mouse.x, mouse.y).y

            // reset start position
            if (!hasStartPosition) {
                startPosition = yPos;
                hasStartPosition = true;
            }

            // set threshold
            if (!passedDragThreshold && Math.abs(y) > dragThreshold) {
                passedDragThreshold = true;
            }

            // update position
            // y < 0 - dragging up (dismissing the app)
            y = Math.min(0, yPos - startPosition);
        }

        onPressedChanged: {
            yAnimator.stop();

            // reset values
            if (pressed) {
                hasStartPosition = false;
                passedDragThreshold = false;
            }

            // run animation when finger lets go
            if (!pressed) {
                if (control.movingUp && control.y < -Kirigami.Units.gridUnit * 2) {
                    yAnimator.to = -control.height;
                } else {
                    yAnimator.to = 0;
                }
                yAnimator.start();
            }
        }

        // if the app doesn't close within a certain time, drag it back
        Timer {
            id: uncloseTimer
            interval: 3000
            onTriggered: {
                yAnimator.to = 0;
                yAnimator.restart();
            }
        }

        NumberAnimation on y {
            id: yAnimator
            running: !control.pressed
            duration: Kirigami.Units.longDuration
            easing.type: Easing.InOutQuad
            to: 0
            onFinished: {
                if (to != 0) { // close app
                    delegate.taskSwitcherHelpers.lastClosedTask = delegate.currentIndex;
                    delegate.closeApp();
                    uncloseTimer.start();
                }
            }
        }

        // application
        ColumnLayout {
            id: column
            anchors.fill: control
            spacing: 0

            // header
            RowLayout {
                id: appHeader

                Kirigami.Theme.inherit: false
                Kirigami.Theme.colorSet: Kirigami.Theme.Complementary

                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: column.height - appView.height
                spacing: Kirigami.Units.smallSpacing * 2
                opacity: delegate.showHeader ? 1 : 0

                Behavior on opacity {
                    NumberAnimation { duration: Kirigami.Units.shortDuration }
                }

                Kirigami.Icon {
                    Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                    Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                    Layout.alignment: Qt.AlignVCenter
                    Layout.leftMargin: Kirigami.Units.smallSpacing
                    source: delegate.window.icon
                }

                // Plasma Fusion: the switcher boards' title (bold, the board's light text)
                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    elide: Text.ElideRight
                    text: delegate.window.caption
                    font.weight: Font.Bold
                    color: "#e8ebf4"
                }

                // Plasma Fusion: a 44 px touch target with a round 30 px fill (TABLET 4.5)
                T.AbstractButton {
                    id: closeButton
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 44
                    implicitHeight: 44
                    z: 99
                    text: i18n("Close %1", delegate.window.caption)
                    Accessible.name: text
                    background: Rectangle {
                        anchors.centerIn: parent
                        width: 30
                        height: 30
                        radius: 15
                        color: Qt.rgba(1, 1, 1, closeButton.down ? 0.24 : closeButton.hovered ? 0.18 : 0.12)
                    }
                    contentItem: Item {
                        Kirigami.Icon {
                            anchors.centerIn: parent
                            width: Kirigami.Units.iconSizes.small
                            height: Kirigami.Units.iconSizes.small
                            source: "window-close-symbolic"
                            color: "#e8ebf4"
                            isMask: true
                        }
                    }
                    onClicked: {
                        delegate.taskSwitcherHelpers.lastClosedTask = delegate.currentIndex;
                        delegate.closeApp()
                    }
                }
            }

            // app preview
            Rectangle {
                id: appView
                Layout.preferredWidth: delegate.taskSwitcherHelpers.previewWidth
                Layout.preferredHeight: delegate.taskSwitcherHelpers.previewHeight
                Layout.maximumWidth: delegate.taskSwitcherHelpers.previewWidth
                Layout.maximumHeight: delegate.taskSwitcherHelpers.previewHeight

                // Plasma Fusion: the window cards' radius 18 and 1 px edge (KWIN-2 switcher boards); a
                // clip alone keeps square corners, so the preview is drawn through the boards' shader.
                radius: 18
                color: Qt.rgba(27 / 255, 32 / 255, 49 / 255, 0.6)

                // scale animation on press
                property real zoomScale: control.pressed ? 0.95 : 1
                Behavior on zoomScale {
                    NumberAnimation {
                        duration: Kirigami.Units.longDuration
                        easing.type: Easing.OutExpo
                    }
                }

                transform: Scale {
                    origin.x: appView.width / 2;
                    origin.y: appView.height / 2;
                    xScale: appView.zoomScale
                    yScale: appView.zoomScale
                }

                Item {
                    id: item
                    anchors.fill: appView
                    // one offscreen layer per card near the current one (about 3 MB each at
                    // 1920 x 1200); cards further away are off screen
                    layer.enabled: Math.abs(delegate.currentIndex - delegate.taskSwitcher.state.currentTaskIndex) <= 2
                    layer.effect: ShaderEffect {
                        readonly property real radius: appView.radius
                        readonly property size boxSize: Qt.size(width, height)
                        fragmentShader: Qt.resolvedUrl("shaders/thumbnail.frag.qsb")
                    }

                    KWinComponents.WindowThumbnail {
                        id: thumbSource
                        wId: delegate.window.internalId
                        anchors.fill: item
                    }

                    Rectangle {
                        anchors.fill: item
                        color: Qt.rgba(0, 0, 0, delegate.darken)
                    }
                }

                Rectangle {
                    anchors.fill: appView
                    radius: appView.radius
                    color: "transparent"
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.10)
                }
            }
        }
    }
}


