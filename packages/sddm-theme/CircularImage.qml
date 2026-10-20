/* SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
 * SPDX-License-Identifier: GPL-2.0-or-later
 *
 * A user photo shown through the circle of its tile. Rectangle's radius rounds nothing of a
 * child, and this greeter's Canvas cannot draw an Image (drawImage fails at load), so the photo
 * stays a square Image underneath and a Canvas paints the four corners in the tile's own fill
 * with an even-odd fill (rect minus circle): the visible window is the circle, and the corners
 * match the tile. The ring reads as the board's translucent ring.
 */

import QtQuick 2.15

Item {
    id: root
    property url source: ""
    property color fill: "transparent"
    readonly property bool ready: photo.status === Image.Ready
    onSourceChanged: canvas.requestPaint()
    onFillChanged: canvas.requestPaint()

    Image {
        id: photo
        anchors.fill: parent
        source: root.source
        fillMode: Image.PreserveAspectCrop
        visible: root.source !== ""
    }
    Canvas {
        id: canvas
        anchors.fill: parent
        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            if (root.source === "") {
                return;
            }
            const r = Math.min(width, height) / 2;
            ctx.beginPath();
            ctx.rect(0, 0, width, height);
            ctx.arc(width / 2, height / 2, r, 0, Math.PI * 2);
            ctx.closePath();
            ctx.fillStyle = root.fill;
            ctx.fill("evenodd");
        }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Component.onCompleted: requestPaint()
    }
    // The window's edge reads as the board's translucent ring
    Rectangle {
        anchors.fill: parent
        radius: Math.min(width, height) / 2
        color: "transparent"
        border.color: "#24ffffff"
        border.width: 1
    }
}
