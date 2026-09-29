/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick

// Section title (14 px, 800) with an optional pill button on the right.
Item {
    id: header

    property FusionColors pal
    property string fontFamily
    property string title
    property string buttonText
    property bool buttonBack: false
    property alias button: pill

    signal buttonClicked()
    signal navTab()
    signal navBacktab()
    signal navUp()
    signal navDown()

    implicitHeight: 26

    FusionText {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: pill.visible ? pill.left : parent.right
        anchors.rightMargin: 8
        text: header.title
        color: header.pal.text
        elide: Text.ElideRight
        family: header.fontFamily
        px: 14
        weight: 800
        Accessible.role: Accessible.Heading
    }

    PillButton {
        id: pill
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        visible: header.buttonText.length > 0
        pal: header.pal
        fontFamily: header.fontFamily
        text: header.buttonText
        back: header.buttonBack
        onClicked: header.buttonClicked()
        Keys.onTabPressed: header.navTab()
        Keys.onBacktabPressed: header.navBacktab()
        Keys.onUpPressed: header.navUp()
        Keys.onDownPressed: header.navDown()
    }
}
