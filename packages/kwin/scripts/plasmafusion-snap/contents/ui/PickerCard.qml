/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Effects
import org.kde.kirigami as Kirigami
import org.kde.kwin

// A window offered for the empty half (TabsSnap board): radius 12, padding 8, fill .06, a live
// preview with a title-bar-like top, app icon and name; selected: accent fill .22 + 2 px ring.
Item {
    id: card

    property FusionPalette pal
    property string fontFamily: "Manrope"
    property var window: null
    property bool selected: false
    property real thumbnailHeight: 140
    readonly property bool hovered: pointer.containsMouse
    readonly property var names: describe(window)

    signal activated()

    implicitHeight: 8 + thumbnailHeight + 8 + labels.height + 8
    height: implicitHeight

    Accessible.role: Accessible.Button
    Accessible.name: names.title.length > 0 ? names.app + ", " + names.title : names.app

    // "Wallpapers — Dolphin" -> app "Dolphin", title "Wallpapers" when the suffix matches the
    // window's application; otherwise the app name comes from its desktop file id.
    function describe(w) {
        if (!w) {
            return { app: "", title: "" };
        }
        const caption = String(w.captionNormal || w.caption || "");
        const keys = [];
        const add = s => {
            const k = String(s || "").toLowerCase().replace(/[^a-z0-9]/g, "");
            if (k.length > 1 && keys.indexOf(k) < 0) {
                keys.push(k);
            }
        };
        const dfn = String(w.desktopFileName || "");
        add(dfn.split(".").pop());
        add(w.resourceClass);
        add(w.resourceName);
        const m = caption.match(/^(.*\S)\s+[—–-]\s+(\S.*)$/);
        if (m) {
            const suffix = m[2].toLowerCase().replace(/[^a-z0-9]/g, "");
            if (keys.some(k => suffix.indexOf(k) >= 0 || k.indexOf(suffix) >= 0)) {
                return { app: m[2], title: m[1] };
            }
        }
        let base = dfn.length > 0 ? dfn.split(".").pop() : String(w.resourceClass || "");
        const known = { "systemsettings": "System Settings", "konsole": "Konsole", "dolphin": "Dolphin",
                        "kwrite": "KWrite", "kate": "Kate", "discover": "Discover" };
        let app = known[base.toLowerCase()] || base.split(/[-_\s]+/).filter(s => s.length > 0)
                                                    .map(s => s.charAt(0).toUpperCase() + s.slice(1)).join(" ");
        if (app.length === 0) {
            return { app: caption, title: "" };
        }
        return { app: app, title: caption === app ? "" : caption };
    }

    Rectangle {
        anchors.fill: parent
        radius: 12
        color: card.selected ? card.pal.selectedFill : card.pal.cardFill
    }

    Rectangle {
        anchors.fill: parent
        radius: 12
        color: "transparent"
        border.width: 2
        border.color: card.pal.zone
        visible: card.selected
    }

    Item {
        id: thumbBox
        x: 8
        y: 8
        width: card.width - 16
        height: card.thumbnailHeight

        Rectangle {
            anchors.fill: parent
            radius: 8
            color: card.pal.thumbFill
        }

        Kirigami.Icon {
            anchors.centerIn: parent
            width: 48
            height: 48
            source: card.window ? card.window.icon : ""
            opacity: 0.8
        }

        Item {
            anchors.fill: parent
            layer.enabled: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: thumbMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
            }

            WindowThumbnail {
                id: thumbnail
                readonly property real sourceWidth: Math.max(1, thumbnail.implicitWidth)
                readonly property real sourceHeight: Math.max(1, thumbnail.implicitHeight)
                readonly property real fit: Math.max(thumbBox.width / sourceWidth, thumbBox.height / sourceHeight)
                client: card.window
                width: Math.ceil(thumbnail.sourceWidth * thumbnail.fit)
                height: Math.ceil(thumbnail.sourceHeight * thumbnail.fit)
                x: Math.round((thumbBox.width - thumbnail.width) / 2)
                y: 0
            }
        }

        Rectangle {
            id: thumbMask
            anchors.fill: parent
            radius: 8
            visible: false
            layer.enabled: true
            layer.smooth: true
        }

        Rectangle {
            anchors.fill: parent
            radius: 8
            color: "transparent"
            border.width: 1
            border.color: card.pal.thumbEdge
        }
    }

    Item {
        id: labels
        x: 8
        y: thumbBox.y + thumbBox.height + 8
        width: card.width - 16
        height: Math.max(20, texts.implicitHeight)

        Kirigami.Icon {
            id: appIcon
            anchors.verticalCenter: parent.verticalCenter
            width: 20
            height: 20
            source: card.window ? card.window.icon : ""
        }

        Column {
            id: texts
            anchors.verticalCenter: parent.verticalCenter
            x: appIcon.width + 8
            width: parent.width - x

            Text {
                width: parent.width
                text: card.names.app
                elide: Text.ElideRight
                maximumLineCount: 1
                textFormat: Text.PlainText
                font.family: card.fontFamily
                font.pointSize: 9.75
                font.weight: Font.ExtraBold
                color: card.pal.text
            }
            Text {
                width: parent.width
                text: card.names.title
                visible: text.length > 0
                elide: Text.ElideRight
                maximumLineCount: 1
                textFormat: Text.PlainText
                font.family: card.fontFamily
                font.pointSize: 8.625
                color: card.pal.muted
            }
        }
    }

    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        onClicked: card.activated()
    }
}
