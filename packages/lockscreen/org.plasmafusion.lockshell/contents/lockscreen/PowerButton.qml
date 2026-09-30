// SPDX-FileCopyrightText: 2016 David Edmundson <davidedmundson@kde.org>
// SPDX-FileCopyrightText: 2024 Noah Davis <noahadvs@gmail.com>
// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: LGPL-2.0-or-later

import QtQuick
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// Login board power button: a 44 px glass circle with an 18 px line icon over an 11.5 px
// label. Keeps the stock action button's mnemonic handling ("Slee&p" -> Alt+P).
T.AbstractButton {
    id: root

    required property FusionMetrics metrics
    property string iconPath: ""

    hoverEnabled: true
    focusPolicy: Qt.TabFocus
    implicitWidth: Math.max(56, column.implicitWidth)
    implicitHeight: column.implicitHeight

    Accessible.name: Kirigami.MnemonicData.plainTextLabel

    Kirigami.MnemonicData.enabled: root.enabled && root.visible
    Kirigami.MnemonicData.controlType: Kirigami.MnemonicData.SecondaryControl
    Kirigami.MnemonicData.label: root.text

    Shortcut {
        // An explicit "&" in the text is handled by the button itself.
        enabled: !(RegExp(/\&[^\&]/).test(root.text))
        sequence: root.Kirigami.MnemonicData.sequence
        onActivated: root.animateClick()
    }

    Motion {
        id: motion
    }

    contentItem: Column {
        id: column
        spacing: root.metrics.px(6)

        Rectangle {
            id: circle
            objectName: "powerCircle"
            anchors.horizontalCenter: parent.horizontalCenter
            // 44 px, 48 in tablet posture (TABLET 4.13).
            width: root.metrics.tablet ? 48 : 44
            height: width
            radius: width / 2
            antialiasing: true
            color: root.hovered || root.visualFocus ? PfStyle.chipFillHover : PfStyle.chipFill
            scale: root.down ? 0.94 : 1

            Behavior on scale {
                enabled: motion.animate
                NumberAnimation { duration: motion.pressScale }
            }

            // The 1 px edge over the fill, as the board's CSS border over its background.
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                antialiasing: true
                color: "transparent"
                border.width: 1
                border.color: PfStyle.chipBorder
            }

            LineIcon {
                anchors.centerIn: parent
                size: 18
                path: root.iconPath
            }
            FocusRing {
                visible: root.visualFocus
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.Kirigami.MnemonicData.richTextLabel
            textFormat: Text.StyledText
            color: PfStyle.textMuted
            font.family: PfStyle.uiFont
            font.pointSize: root.metrics.font(11.5) * 0.75 // 11.5 px at 96 dpi
            font.weight: Font.DemiBold
            font.styleName: PfStyle.bold
        }
    }

    Keys.onEnterPressed: clicked()
    Keys.onReturnPressed: clicked()
}
