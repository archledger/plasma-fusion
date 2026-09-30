// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import org.kde.kirigami as Kirigami

// Login board: the 112 px round avatar (the user's picture, or the first letter of the name
// in Space Grotesk 46 px on #7b5cd6) with a 4 px light ring and a soft shadow, then the name
// in Space Grotesk 28 px, 16 px apart.
Column {
    id: header

    required property FusionMetrics metrics
    property string userName: ""
    property url userIcon: ""

    readonly property string initial: {
        const name = userName.trim();
        if (name.length === 0) {
            return "?";
        }
        const cp = name.codePointAt(0);
        return String.fromCodePoint(cp).toLocaleUpperCase(Qt.locale().name.replace("_", "-"));
    }

    spacing: metrics.px(16)

    Item {
        id: avatarBox
        anchors.horizontalCenter: parent.horizontalCenter
        width: 112
        height: 112

        Kirigami.ShadowedRectangle {
            anchors.centerIn: parent
            width: 112
            height: 112
            radius: 56
            color: PfStyle.avatarFill
            shadow.size: 50
            shadow.yOffset: 20
            shadow.color: PfStyle.shadow

            Text {
                anchors.centerIn: parent
                visible: picture.status !== Image.Ready
                text: header.initial
                color: "#ffffff"
                font.family: PfStyle.displayFont
                font.pixelSize: 46
                font.weight: Font.DemiBold
                font.styleName: PfStyle.bold
                textFormat: Text.PlainText
            }
        }

        Image {
            id: picture
            anchors.centerIn: parent
            width: 112
            height: 112
            visible: false
            source: header.userIcon
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: 112 * Screen.devicePixelRatio
            sourceSize.height: 112 * Screen.devicePixelRatio
        }
        Kirigami.ShadowedTexture {
            anchors.centerIn: parent
            width: 112
            height: 112
            radius: 56
            color: "transparent"
            visible: picture.status === Image.Ready
            source: picture
        }

        // The ring sits just outside the avatar (CSS box-shadow 0 0 0 4px).
        Rectangle {
            anchors.fill: parent
            anchors.margins: -4
            radius: width / 2
            antialiasing: true
            color: "transparent"
            border.width: 4
            border.color: PfStyle.avatarRing
        }
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(implicitWidth, header.metrics.px(400))
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        text: header.userName
        color: PfStyle.text
        font.family: PfStyle.displayFont
        font.pixelSize: header.metrics.font(28)
        font.weight: Font.DemiBold
        textFormat: Text.PlainText
    }
}
