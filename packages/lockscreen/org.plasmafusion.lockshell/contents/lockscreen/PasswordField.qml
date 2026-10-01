// SPDX-FileCopyrightText: 2019 Carl-Lucien Schwan <carl@carlschwan.eu>
// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: LGPL-2.0-or-later

import QtQuick
import QtQuick.Templates as T

// The text part of the Login board's password pill: Manrope 16 px, bullets 0.2 em apart,
// placeholder #8f98b3. Keeps the Plasma password field's safety rules: no undo, Ctrl+Shift+U
// clears, sensitive input-method hints.
T.TextField {
    id: field

    required property FusionMetrics metrics
    property bool showPassword: false

    echoMode: showPassword ? TextInput.Normal : TextInput.Password
    passwordCharacter: "•"
    inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText | Qt.ImhSensitiveData
    selectByMouse: true
    verticalAlignment: TextInput.AlignVCenter
    padding: 0

    color: PfStyle.text
    selectionColor: PfStyle.accentStrong
    selectedTextColor: PfStyle.textOnAccent
    placeholderTextColor: PfStyle.placeholder

    font.family: PfStyle.uiFont
    font.pixelSize: metrics.font(16)
    font.letterSpacing: echoMode === TextInput.Password && length > 0 ? metrics.font(3.2) : 0

    implicitHeight: metrics.px(36)
    implicitWidth: 200

    Accessible.name: placeholderText
    Accessible.passwordEdit: true

    // A finger or pen on the field (TABLET2 P0): the lock screen asks KWin for the on-screen
    // keyboard, which a mouse click must not bring up.
    signal touched()
    PointHandler {
        acceptedDevices: PointerDevice.TouchScreen | PointerDevice.Stylus
        onActiveChanged: {
            if (active) {
                field.touched();
            }
        }
    }

    Text {
        anchors.fill: parent
        verticalAlignment: Text.AlignVCenter
        visible: field.length === 0 && field.preeditText.length === 0
        text: field.placeholderText
        color: field.placeholderTextColor
        font.family: PfStyle.uiFont
        font.pixelSize: field.metrics.font(16)
        elide: Text.ElideRight
        textFormat: Text.PlainText
    }

    Shortcut {
        // Also supported by su and sudo.
        sequence: "Ctrl+Shift+U"
        enabled: field.activeFocus
        onActivated: field.clear()
    }

    Keys.onPressed: event => {
        if (event.matches(StandardKey.Undo)) {
            // No undo in password fields (QTBUG-103934).
            event.accepted = true;
        }
    }
}
