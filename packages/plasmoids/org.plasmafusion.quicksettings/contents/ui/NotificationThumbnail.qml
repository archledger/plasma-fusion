// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

import "components"

// The preview of a file a notification links to (x-kde-urls: Spectacle's screenshot, a received
// file), as the stock applet's ThumbnailStrip: the strip is Plasma's "enormous" icon size tall and
// the preview fits in it, its aspect kept. A click, Return or Space opens the file. The preview
// comes from KIO's thumbnailer as the stock applet makes it (NotificationPreview.qml, which uses
// the applet's own Thumbnailer type, loaded in the same shell); where that cannot load, an image
// file is drawn by itself and any other file shows a generic icon.
T.AbstractButton {
    id: thumb

    required property FusionPalette pal
    required property FusionMetrics metrics
    property url url

    readonly property string fileName: {
        const path = String(url).replace(/\/+$/, "");
        return decodeURIComponent(path.slice(path.lastIndexOf("/") + 1));
    }
    // Which preview is drawn: "kio" (the stock thumbnailer), "image" (the file itself) or "icon".
    readonly property string previewKind: kio.status === Loader.Ready ? "kio" : (plain.status === Image.Ready ? "image" : "icon")

    implicitHeight: Kirigami.Units.iconSizes.enormous
    focusPolicy: Qt.TabFocus
    hoverEnabled: true
    Accessible.role: Accessible.Button
    Accessible.name: i18nc("@action:button %1 file name", "Open %1", fileName)
    Keys.onReturnPressed: thumb.clicked()
    Keys.onEnterPressed: thumb.clicked()

    background: Rectangle {
        radius: 12
        color: thumb.down ? thumb.pal.overlay(0.12) : (thumb.hovered ? thumb.pal.overlay(0.09) : thumb.pal.overlay(0.06))
        FocusRing {
            baseRadius: 12
            ringColor: thumb.pal.focus
            shown: thumb.visualFocus
        }
    }

    contentItem: Item {
        Loader {
            id: kio
            anchors.fill: parent
            anchors.margins: 4
            active: thumb.url.toString() !== ""
            source: "NotificationPreview.qml"
            onLoaded: {
                item.url = Qt.binding(() => thumb.url);
                item.size = Qt.binding(() => Qt.size(Math.round(thumb.width * Screen.devicePixelRatio),
                                                      Math.round(thumb.width * Screen.devicePixelRatio)));
            }
        }
        Image {
            id: plain
            anchors.fill: parent
            anchors.margins: 4
            visible: thumb.previewKind === "image"
            source: kio.status === Loader.Error ? thumb.url : ""
            sourceSize.width: Math.round(width * Screen.devicePixelRatio)
            asynchronous: true
            fillMode: Image.PreserveAspectFit
            smooth: true
        }
        Kirigami.Icon {
            anchors.centerIn: parent
            width: Kirigami.Units.iconSizes.huge
            height: width
            visible: thumb.previewKind === "icon" && kio.status !== Loader.Loading && plain.status !== Image.Loading
            source: "unknown"
        }
    }
}
