/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Templates as T
import org.kde.plasma.core as PlasmaCore

// The first time tablet mode turns on (TABLET 5, P2): one card, centred on the screen, with the
// gestures (TABLET2: home and the app switcher, the dock, the previous app, the two pull-downs,
// home search; KWin's three-finger Overview is off in tablet posture) and a "Got it" button. The dock writes plasmafusionrc [Tablet]
// GestureCardShown=true when it is dismissed, so it never comes back.
PlasmaCore.Dialog {
    id: card

    required property DockPalette pal
    required property Motion motion
    property rect screenGeometry

    signal dismissed()

    type: PlasmaCore.Dialog.Normal
    location: PlasmaCore.Types.Floating
    flags: Qt.WindowStaysOnTopHint
    hideOnWindowDeactivate: false
    x: screenGeometry.x + Math.round((screenGeometry.width - width) / 2)
    y: screenGeometry.y + Math.round((screenGeometry.height - height) / 2)
    visible: screenGeometry.width > 0

    mainItem: FocusScope {
        width: 420 - card.margins.left - card.margins.right
        height: content.implicitHeight
        focus: true
        Keys.onEscapePressed: card.dismissed()

        Column {
            id: content
            width: parent.width
            spacing: 14
            topPadding: 8
            bottomPadding: 8

            Text {
                width: parent.width
                text: i18nc("@title", "Touch gestures")
                color: card.pal.ink
                font.pixelSize: 18
                font.weight: Font.ExtraBold
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }

            Repeater {
                model: [
                    { "path": "M6 20h12M12 16V4M8 8l4-4 4 4", "text": i18nc("@info", "Swipe up from the bottom to go home; pause halfway to see your apps") },
                    { "path": "M6 20h12M9 14l3-3 3 3", "text": i18nc("@info", "A short swipe up shows the dock over an app") },
                    { "path": "M4 18h16M8 14l-4 4 4 4M16 14l4 4-4 4", "text": i18nc("@info", "Swipe along the bottom edge for the previous app") },
                    { "path": "M6 4h12M12 8v12M8 16l4 4 4-4", "text": i18nc("@info", "Pull down at the clock for notifications, at the battery for controls") },
                    { "path": "M11 4a6 6 0 1 0 0 12a6 6 0 0 0 0-12M15.5 15.5L20 20", "text": i18nc("@info", "Swipe down on the home screen to search") }
                ]
                Row {
                    id: gestureRow
                    required property var modelData
                    width: content.width
                    spacing: 14
                    Rectangle {
                        width: 48
                        height: 48
                        radius: 14
                        color: Qt.rgba(card.pal.ink.r, card.pal.ink.g, card.pal.ink.b, 0.08)
                        Glyph {
                            anchors.centerIn: parent
                            size: 28
                            color: card.pal.ink
                            path: gestureRow.modelData.path
                        }
                    }
                    Text {
                        width: content.width - 62
                        anchors.verticalCenter: parent.verticalCenter
                        text: gestureRow.modelData.text
                        color: card.pal.ink
                        font.pixelSize: 14
                        font.weight: Font.Bold
                        wrapMode: Text.WordWrap
                        textFormat: Text.PlainText
                    }
                }
            }

            T.AbstractButton {
                id: gotIt
                anchors.horizontalCenter: parent.horizontalCenter
                width: 160
                height: 44
                focus: true
                text: i18nc("@action:button", "Got it")
                Accessible.name: text
                onClicked: card.dismissed()
                Keys.onReturnPressed: clicked()
                Keys.onEnterPressed: clicked()
                background: Rectangle {
                    radius: 22
                    color: card.pal.accentFill
                    opacity: gotIt.down ? 0.85 : 1
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: -3
                        radius: 25
                        color: "transparent"
                        border.width: 2
                        border.color: card.pal.focusRing
                        visible: gotIt.visualFocus
                    }
                }
                contentItem: Text {
                    text: gotIt.text
                    color: card.pal.accentText
                    font.pixelSize: 14
                    font.weight: Font.ExtraBold
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    textFormat: Text.PlainText
                }
            }
        }
    }
}
