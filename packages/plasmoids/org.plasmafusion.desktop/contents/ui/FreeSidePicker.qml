/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later

    The free side's app picker (board TabletSplit.dc.html): in tablet posture, in the part of the
    screen beside an app that fills a half (HomeLayer.freeSide), "Pick an app for this side" over
    the wallpaper, under the tint of "Pick a window for this side" (the snap script's FillPicker),
    with the home apps first (the pinned list, in the home pages' order) and then every app A to Z.
    The app already on the other side is dimmed and takes no tap. A tap opens the app on this side
    (HomeLayer.pickForSide).
*/
import QtQuick
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

import "code/home.js" as HomeLogic

Item {
    id: picker

    required property var home
    required property string side
    // The app beside the free part (the task model's AppId).
    required property string otherApp

    readonly property bool dark: {
        const c = Kirigami.Theme.backgroundColor;
        return (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) < 0.5;
    }
    // The board's tint (rgba(8,11,24,.55); light: rgba(250,251,255,.62)), heading and labels.
    readonly property color fill: dark ? Qt.rgba(8 / 255, 11 / 255, 24 / 255, 0.55) : Qt.rgba(250 / 255, 251 / 255, 1, 0.62)
    readonly property color headingColor: dark ? "#dfe3ee" : "#141827"
    readonly property color mutedColor: dark ? "#a3abc2" : "#5b6278"
    readonly property color nameColor: dark ? "#ffffff" : "#141827"
    // 128 x 120 px cells, 40 px from the sides, as many columns as fit.
    readonly property int cellWidth: 128
    readonly property int cellHeight: 120
    readonly property int columns: Math.max(1, Math.floor((width - 80) / cellWidth))

    readonly property string title: i18nc("@label the apps offered beside an app in one half of the screen", "Pick an app for this side")

    Accessible.role: Accessible.Pane
    Accessible.name: title

    Rectangle {
        anchors.fill: parent
        color: picker.fill
    }

    GridView {
        id: grid
        objectName: "freeSideApps"
        x: 40
        width: picker.columns * picker.cellWidth
        height: parent.height
        topMargin: 30
        bottomMargin: 48
        cellWidth: picker.cellWidth
        cellHeight: picker.cellHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        model: picker.home.allModel
        Accessible.role: Accessible.List
        Accessible.name: i18nc("@label", "All apps")

        header: Column {
            width: grid.width
            spacing: 14
            Text {
                text: picker.title
                textFormat: Text.PlainText
                color: picker.headingColor
                font.pixelSize: picker.home.metrics.font(17)
                font.weight: Font.ExtraBold
            }
            SectionLabel {
                topPadding: 6
                text: i18nc("@title the home screen's apps, in capitals on the board", "Home")
            }
            Grid {
                columns: picker.columns
                Accessible.role: Accessible.List
                Accessible.name: i18nc("@label", "Home screen apps")
                Repeater {
                    model: picker.home.favoritesModel
                    delegate: PickTile {}
                }
            }
            SectionLabel {
                topPadding: 4
                bottomPadding: 14
                text: i18nc("@title every app, A to Z, in capitals on the board", "All apps")
            }
        }
        delegate: PickTile {}
    }

    // The list goes on under a fade into the tint.
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 120
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(picker.fill.r, picker.fill.g, picker.fill.b, 0) }
            GradientStop { position: 1; color: picker.fill }
        }
    }

    component SectionLabel: Text {
        readonly property real size: picker.home.metrics.font(12)
        textFormat: Text.PlainText
        color: picker.mutedColor
        font.pixelSize: size
        font.weight: Font.ExtraBold
        font.capitalization: Font.AllUppercase
        // 0.08 em, as on the board (from the size, not font.pixelSize: one font group, a loop)
        font.letterSpacing: 0.08 * size
    }

    component PickTile: T.AbstractButton {
        id: tile
        required property int index
        required property var model
        // Only apps go to a side (a pinned file or link is not offered).
        readonly property string appId: picker.home.splitAppId(String(tile.model.favoriteId || ""))
        readonly property bool beside: HomeLogic.sameApp(appId, picker.otherApp)

        visible: appId !== ""
        enabled: !beside
        width: picker.cellWidth
        height: picker.cellHeight
        text: tile.model.display || ""
        Accessible.role: Accessible.Button
        Accessible.name: beside ? i18nc("@label %1 app name", "%1, already on the other side", text) : text
        onClicked: picker.home.pickForSide(icon, tile.model, picker.side, tile.appId)

        background: Item {}
        contentItem: Item {
            opacity: tile.beside ? 0.4 : 1
            scale: tile.down ? 0.94 : 1
            Behavior on scale {
                enabled: picker.home.motion.animate
                NumberAnimation {
                    duration: picker.home.motion.press
                    easing.type: picker.home.motion.standardEasing
                }
            }
            FusionShadow {
                anchors.fill: icon
                offset.y: 3
                blur: 8
                radius: 0.234 * icon.size
                color: Qt.rgba(0, 0, 0, 0.30)
            }
            FusionIconTile {
                id: icon
                x: (parent.width - width) / 2
                size: 72
                source: tile.model.decoration || "application-x-executable"
                iconName: picker.home.iconNameFor(tile.model)
                calendarDate: true
            }
            Text {
                anchors.top: icon.bottom
                anchors.topMargin: 10
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - 12
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                maximumLineCount: 1
                text: tile.text
                textFormat: Text.PlainText
                color: picker.nameColor
                style: picker.dark ? Text.Raised : Text.Normal
                styleColor: Qt.rgba(0, 0, 0, 0.45)
                font.pixelSize: picker.home.metrics.font(13)
                font.weight: Font.DemiBold
            }
        }
    }
}
