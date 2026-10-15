// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Window
import org.kde.kirigami as Kirigami

// A picture, whole and centred: scaled down to fit, never up (a small icon stays sharp). Moving
// pictures (GIF, WebP with several frames) play.
Item {
    id: viewer
    objectName: "imageViewer"

    // QuickLookItem (quicklook.h).
    required property var item
    readonly property Item picture: frames.item
    readonly property bool ready: picture !== null && (picture.status === Image.Ready || picture.status === Image.Error)
    readonly property var report: picture ? ({
        status: picture.status === Image.Ready ? "ready" : "error",
        width: picture.implicitWidth,
        height: picture.implicitHeight,
        paintedWidth: Math.round(picture.paintedWidth),
        paintedHeight: Math.round(picture.paintedHeight),
        animated: item.kind === "animation"
    }) : ({})
    readonly property string extra: ""

    Loader {
        id: frames
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        sourceComponent: viewer.item.kind === "animation" ? moving : still
    }

    Component {
        id: still
        Image {
            source: viewer.item.url
            asynchronous: true
            autoTransform: true
            cache: false
            smooth: true
            mipmap: true
            // Decoded at the size it is shown (a large photo does not need all its pixels).
            sourceSize: Qt.size(Math.max(1, width * Screen.devicePixelRatio), Math.max(1, height * Screen.devicePixelRatio))
            fillMode: implicitWidth > width || implicitHeight > height ? Image.PreserveAspectFit : Image.Pad
        }
    }
    Component {
        id: moving
        AnimatedImage {
            source: viewer.item.url
            asynchronous: true
            cache: false
            smooth: true
            playing: true
            fillMode: implicitWidth > width || implicitHeight > height ? Image.PreserveAspectFit : Image.Pad
        }
    }
}
