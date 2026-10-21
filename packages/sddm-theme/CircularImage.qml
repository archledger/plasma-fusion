/* SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
 * SPDX-License-Identifier: GPL-2.0-or-later
 *
 * A user photo cut to the circle of its tile. Rectangle's radius rounds nothing of a child and
 * this greeter's Canvas cannot draw an Image (drawImage fails at load), so the cut is MultiEffect's
 * mask (CircularMask.qml, QtQuick.Effects). Painting the square's corners in the tile's fill does
 * not work: the tile is a disc, so those corners lie on the wallpaper and showed as a square on a
 * real greeter (Debian testing, 2026-10-21). The mask needs the hardware scene graph (effects do
 * not draw in the software one) and the module; without either the photo is not drawn at all and
 * the tile keeps its initial (ready stays false) - never a square photo.
 */

import QtQuick 2.15

Item {
    id: root
    property url source: ""
    // Created here, not by a Loader's URL: a greeter without QtQuick.Effects then only gets an
    // error status, where a Loader would print a warning at every start.
    readonly property Component maskComponent: Qt.createComponent("CircularMask.qml")
    readonly property bool hardware: GraphicsInfo.api !== GraphicsInfo.Unknown
                                     && GraphicsInfo.api !== GraphicsInfo.Software
    readonly property bool ready: photo.status === Image.Ready && mask.status === Loader.Ready

    Image {
        id: photo
        anchors.fill: parent
        source: root.source
        fillMode: Image.PreserveAspectCrop
        // Drawn only through the mask
        visible: false
    }
    Loader {
        id: mask
        anchors.fill: parent
        active: root.source != "" && root.hardware && root.maskComponent.status === Component.Ready
        sourceComponent: root.maskComponent
        onLoaded: item.photo = photo
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
