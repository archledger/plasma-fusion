/* SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
 * SPDX-License-Identifier: GPL-2.0-or-later
 *
 * Complete PAM instructions without letting unbounded text cover the login controls.
 * QtQuick-only scrolling and paging; see docs/parts/sddm.md for the upstream contracts.
 */

import QtQuick 2.15
import "palette.js" as Palette

Flickable {
    id: messageView
    property alias text: label.text
    property real heightBudget: Number.POSITIVE_INFINITY
    readonly property real lineStep: label.implicitHeight / Math.max(1, label.lineCount)
    // A readable line takes precedence over a smaller budget; the caller keeps footer clearance.
    height: Math.min(contentHeight, Math.max(label.font.pixelSize + 8, heightBudget))
    contentWidth: width
    contentHeight: label.implicitHeight + 4
    clip: true
    flickableDirection: Flickable.VerticalFlick
    boundsBehavior: Flickable.StopAtBounds
    activeFocusOnTab: contentHeight > height
    Accessible.name: qsTr("Authentication message")
    Accessible.description: text

    function scrollBy(delta) {
        contentY = Math.max(0, Math.min(contentY + delta, contentHeight - height));
    }
    onTextChanged: contentY = 0
    onContentHeightChanged: scrollBy(0)
    onHeightChanged: scrollBy(0)
    Keys.onUpPressed: scrollBy(-lineStep)
    Keys.onDownPressed: scrollBy(lineStep)
    Keys.onPressed: event => {
        if (event.key === Qt.Key_PageDown) {
            scrollBy(height);
        } else if (event.key === Qt.Key_PageUp) {
            scrollBy(-height);
        } else if (event.key === Qt.Key_Home) {
            contentY = 0;
        } else if (event.key === Qt.Key_End) {
            contentY = Math.max(0, contentHeight - height);
        } else {
            event.accepted = false;
            return;
        }
        event.accepted = true;
    }

    Text {
        id: label
        x: 2
        y: 2
        width: Math.max(0, messageView.width - 4)
        font.family: Palette.bodyFont
        font.pixelSize: 12
        font.weight: Font.Bold
        color: Palette.warnInk
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
    }
    Rectangle {
        // The focus frame belongs to the viewport, not its moving contentItem.
        parent: messageView
        anchors.fill: parent
        color: "transparent"
        border.color: Palette.accent
        border.width: messageView.activeFocus ? 1 : 0
        z: 1
    }
}
