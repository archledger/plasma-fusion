/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Templates as T

// Search field of the launcher: 50 px pill, 1.5 px accent border while focused, "Meta" hint badge.
// Heights, paddings and the text follow the user's text size (`metrics`); the border does not.
FocusScope {
    id: box

    property FusionColors pal
    property FusionMetrics metrics
    property alias text: input.text
    property alias input: input

    signal navigateDown()
    signal navigateTab(bool backwards)
    signal accepted()
    signal escapePressed()

    implicitHeight: metrics.px(50)

    function clear() {
        input.clear();
    }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: box.pal.field
        border.width: 1.5
        border.color: input.activeFocus ? box.pal.fieldBorder : box.pal.fieldBorderIdle
        antialiasing: true
    }

    Glyph {
        id: searchGlyph
        // 1.5 px border + 18 px padding (the board's box-sizing: border-box).
        x: 1.5 + box.metrics.px(18)
        anchors.verticalCenter: parent.verticalCenter
        name: "search"
        size: box.metrics.px(20)
        color: box.pal.textSecondary
    }

    TextInput {
        id: input
        focus: true
        anchors.left: searchGlyph.right
        anchors.leftMargin: box.metrics.px(12)
        anchors.right: trailing.left
        anchors.rightMargin: box.metrics.px(12)
        anchors.verticalCenter: parent.verticalCenter
        clip: true
        color: box.pal.text
        selectionColor: box.pal.accent
        selectedTextColor: "#ffffff"
        selectByMouse: true
        font.family: box.metrics.family
        font.pointSize: box.metrics.font(14.5) * 0.75
        inputMethodHints: Qt.ImhNoPredictiveText
        Accessible.role: Accessible.EditableText
        Accessible.name: i18nc("@label:textbox", "Search")
        Accessible.searchEdit: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: event => {
            switch (event.key) {
            case Qt.Key_Down:
                box.navigateDown();
                event.accepted = true;
                break;
            case Qt.Key_Tab:
                box.navigateTab(false);
                event.accepted = true;
                break;
            case Qt.Key_Backtab:
                box.navigateTab(true);
                event.accepted = true;
                break;
            case Qt.Key_Return:
            case Qt.Key_Enter:
                box.accepted();
                event.accepted = true;
                break;
            case Qt.Key_Escape:
                box.escapePressed();
                event.accepted = true;
                break;
            default:
                break;
            }
        }

        Text {
            anchors.fill: parent
            verticalAlignment: Text.AlignVCenter
            visible: input.text.length === 0 && !input.preeditText
            text: i18nc("@info:placeholder", "Search apps, files and settings — or type a command")
            color: box.pal.placeholder
            elide: Text.ElideRight
            font: input.font
        }
    }

    Item {
        id: trailing
        anchors.right: parent.right
        anchors.rightMargin: box.metrics.px(8)
        anchors.verticalCenter: parent.verticalCenter
        width: input.text.length > 0 ? clearButton.width : badge.width
        height: box.metrics.px(30)

        // Hint that the Meta key opens the launcher.
        Rectangle {
            id: badge
            visible: input.text.length === 0
            anchors.right: parent.right
            width: badgeRow.implicitWidth + box.metrics.px(20)
            height: box.metrics.px(30)
            radius: height / 2
            color: box.pal.badge
            antialiasing: true

            Row {
                id: badgeRow
                anchors.centerIn: parent
                spacing: box.metrics.px(6)

                Glyph {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "meta"
                    size: box.metrics.px(13)
                    color: box.pal.muted
                }

                FusionText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: i18nc("@label name of the Meta (Super) key", "Meta")
                    color: box.pal.muted
                    metrics: box.metrics
                    px: 11.5
                    weight: 800
                }
            }
        }

        T.AbstractButton {
            id: clearButton
            visible: input.text.length > 0
            anchors.right: parent.right
            width: box.metrics.px(30)
            height: width
            hoverEnabled: true
            focusPolicy: Qt.NoFocus
            Accessible.name: i18nc("@action:button", "Clear search")
            onClicked: {
                input.clear();
                input.forceActiveFocus();
            }

            background: Rectangle {
                radius: height / 2
                color: clearButton.hovered ? box.pal.chipHover : box.pal.badge
                antialiasing: true
            }

            contentItem: Item {
                Glyph {
                    anchors.centerIn: parent
                    name: "clear"
                    size: box.metrics.px(14)
                    color: box.pal.textSecondary
                }
            }
        }
    }
}
