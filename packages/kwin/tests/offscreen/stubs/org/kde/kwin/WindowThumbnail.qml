// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
// Offscreen test stand-in for KWin.WindowThumbnail: draws a schematic window like the boards'
// thumbnails from the fake window's "look" (test use only).
import QtQuick
import org.kde.kwin as KWin

Item {
    id: thumb
    property var wId
    property var client
    readonly property var win: {
        const all = KWin.Workspace.windows;
        for (let i = 0; i < all.length; ++i) {
            if (String(all[i].internalId) === String(wId) || all[i] === client) {
                return all[i];
            }
        }
        return null;
    }
    readonly property var look: win && win.look ? win.look : null
    implicitWidth: win ? win.width : 0
    implicitHeight: win ? win.height : 0

    // Painted like KWin: the frame scaled to fit, keeping the aspect ratio.
    Item {
        readonly property real s: Math.min(thumb.width / Math.max(1, thumb.implicitWidth), thumb.height / Math.max(1, thumb.implicitHeight))
        width: thumb.implicitWidth * s
        height: thumb.implicitHeight * s
        anchors.centerIn: parent
        visible: thumb.look !== null
        Rectangle { anchors.fill: parent; color: thumb.look ? thumb.look.body : "transparent" }
        Rectangle { width: parent.width; height: parent.height * 0.12; color: thumb.look ? thumb.look.bar : "transparent" }
        Column {
            x: parent.width * 0.06; y: parent.height * 0.2; width: parent.width * 0.88; spacing: parent.height * 0.05
            Rectangle { height: 8 * parent.width / 176; radius: height / 2; width: parent.width * (thumb.look ? thumb.look.l[0] : 0) / 100; color: thumb.look ? thumb.look.c1 : "transparent" }
            Rectangle { height: 6 * parent.width / 176; radius: height / 2; width: parent.width * (thumb.look ? thumb.look.l[1] : 0) / 100; color: thumb.look ? thumb.look.c2 : "transparent" }
            Rectangle { height: 6 * parent.width / 176; radius: height / 2; width: parent.width * (thumb.look ? thumb.look.l[2] : 0) / 100; color: thumb.look ? thumb.look.c2 : "transparent" }
        }
        Rectangle {
            x: parent.width * 0.06; y: parent.height * 0.7; height: parent.height * 0.22; radius: 5
            width: parent.width * 0.88 * (thumb.look ? thumb.look.l[3] : 0) / 100; color: thumb.look ? thumb.look.c3 : "transparent"
        }
    }
}
