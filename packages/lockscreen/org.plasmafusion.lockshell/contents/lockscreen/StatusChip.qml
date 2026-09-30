// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import org.kde.plasma.workspace.components as PW
import org.kde.plasma.private.battery

// Lock board, bottom right: a 40 px glass chip with the keyboard layout badge ("EN"), the
// virtual keyboard toggle (when an input method is available), network and battery.
GlassPanel {
    id: chip

    required property FusionMetrics metrics
    property bool virtualKeyboardAvailable: false
    property bool virtualKeyboardActive: false

    signal virtualKeyboardToggled()
    signal interacted()

    readonly property bool hasLayout: layoutBadge.name.length > 0
    // qmllint disable missing-property
    readonly property bool hasNetwork: network.status === Loader.Ready && network.item !== null && network.item.available === true
    // qmllint enable missing-property
    readonly property bool hasBattery: batteryControl.hasInternalBatteries
    readonly property bool hasContent: hasLayout || virtualKeyboardAvailable || hasNetwork || hasBattery

    implicitWidth: row.implicitWidth + metrics.px(32)
    // 40 px; in tablet posture 48, with a 48 px keyboard button (TABLET 4.13).
    implicitHeight: metrics.tablet ? Math.max(48, metrics.px(40)) : metrics.px(40)
    radius: height / 2
    visible: hasContent

    PW.KeyboardLayoutSwitcher {
        id: layoutSwitcher
        visible: false
        acceptedButtons: Qt.NoButton
    }

    BatteryControlModel {
        id: batteryControl
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: chip.metrics.px(14)

        // Keyboard layout: the badge switches to the next layout when there are several.
        Rectangle {
            id: layoutBadge
            readonly property string name: (layoutSwitcher.layoutNames.displayName || layoutSwitcher.layoutNames.shortName || "").toUpperCase()
            readonly property bool switchable: layoutSwitcher.hasMultipleKeyboardLayouts

            anchors.verticalCenter: parent.verticalCenter
            visible: chip.hasLayout
            width: badgeText.implicitWidth + chip.metrics.px(14)
            height: chip.metrics.px(21)
            radius: 5
            antialiasing: true
            color: badgeMouse.containsMouse && switchable ? PfStyle.chipFill : "transparent"
            border.width: 1
            border.color: PfStyle.layoutBadgeBorder
            activeFocusOnTab: switchable

            Accessible.role: switchable ? Accessible.Button : Accessible.StaticText
            Accessible.name: layoutSwitcher.layoutNames.longName || name
            Accessible.description: switchable ? i18ndc("plasma_shell_org.kde.plasma.desktop", "Button to change keyboard layout", "Switch layout") : ""
            Accessible.onPressAction: switchLayout()

            function switchLayout() {
                if (switchable) {
                    layoutSwitcher.keyboardLayout.switchToNextLayout();
                    chip.interacted();
                }
            }

            Keys.onSpacePressed: switchLayout()
            Keys.onReturnPressed: switchLayout()
            Keys.onEnterPressed: switchLayout()

            Text {
                id: badgeText
                anchors.centerIn: parent
                text: layoutBadge.name
                color: PfStyle.text
                font.family: PfStyle.uiFont
                font.pixelSize: chip.metrics.font(11)
                font.weight: Font.DemiBold
                font.styleName: PfStyle.extraBold
                textFormat: Text.PlainText
            }
            MouseArea {
                id: badgeMouse
                anchors.fill: parent
                anchors.margins: -6
                hoverEnabled: true
                enabled: layoutBadge.switchable
                cursorShape: Qt.PointingHandCursor
                onClicked: layoutBadge.switchLayout()
                onWheel: wheel => {
                    if (wheel.angleDelta.y > 0) {
                        layoutSwitcher.keyboardLayout.switchToPreviousLayout();
                    } else if (wheel.angleDelta.y < 0) {
                        layoutSwitcher.keyboardLayout.switchToNextLayout();
                    }
                }
            }
            FocusRing {
                controlRadius: 5
                visible: layoutBadge.activeFocus
            }
        }

        RoundButton {
            id: keyboardButton
            objectName: "keyboardButton"
            anchors.verticalCenter: parent.verticalCenter
            visible: chip.virtualKeyboardAvailable
            implicitWidth: chip.metrics.tablet ? 48 : 28
            implicitHeight: implicitWidth
            iconSize: 18
            iconPath: PfStyle.iconKeyboard
            foreground: chip.virtualKeyboardActive ? PfStyle.accent : PfStyle.text
            text: i18ndc("plasma_shell_org.kde.plasma.desktop", "Button to show/hide virtual keyboard", "Virtual Keyboard")
            onClicked: {
                chip.virtualKeyboardToggled();
                chip.interacted();
            }
        }

        Loader {
            id: network
            anchors.verticalCenter: parent.verticalCenter
            source: "NetworkIndicator.qml"
            visible: chip.hasNetwork
            width: visible ? chip.metrics.px(17) : 0
            height: chip.metrics.px(17)
        }

        Row {
            id: battery
            anchors.verticalCenter: parent.verticalCenter
            visible: chip.hasBattery
            spacing: chip.metrics.px(5)

            Accessible.role: Accessible.Indicator
            Accessible.name: i18nd("plasma_lookandfeel_org.kde.lookandfeel", "Battery at %1%", batteryControl.percent)

            LineIcon {
                anchors.verticalCenter: parent.verticalCenter
                size: chip.metrics.px(19)
                path: PfStyle.iconBattery
                fillPath: PfStyle.batteryFill(batteryControl.percent)
                fillColor: batteryControl.percent <= 10 && !batteryControl.pluggedIn ? "#ff6b6b"
                         : batteryControl.percent <= 30 && !batteryControl.pluggedIn ? PfStyle.warning : PfStyle.text
                overlayPath: batteryControl.pluggedIn ? PfStyle.iconBolt : ""
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: i18nd("plasma_lookandfeel_org.kde.lookandfeel", "%1%", batteryControl.percent)
                color: PfStyle.text
                font.family: PfStyle.uiFont
                font.pixelSize: chip.metrics.font(13)
                font.weight: Font.DemiBold
                font.styleName: PfStyle.bold
                textFormat: Text.PlainText
            }
        }
    }
}
