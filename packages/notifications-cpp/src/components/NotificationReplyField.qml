/*
    SPDX-FileCopyrightText: 2019 Kai Uwe Broulik <kde@broulik.de>
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>

    SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
*/

// Plasma Fusion changes in this file are marked "Plasma Fusion": the banner keyboard triage of
// SPEC-notification-triage.md.

import QtQuick
import QtQuick.Layouts

import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

import plasma.applet.org.kde.plasma.notifications as Notifications

RowLayout {
    id: replyRow

    // Plasma Fusion: marks this as the reply field of the notification. The banner asks the
    // ancestors of the item that has the keyboard focus (BannerTriage.inReplyField).
    readonly property bool isReplyField: true

    // implicitWidth will keep being rewritten by the Layout itself
    Layout.maximumWidth: Notifications.Globals.popupWidth
    required property ModelInterface modelInterface

    signal beginReplyRequested

    spacing: Kirigami.Units.smallSpacing

    function activate() {
        replyTextField.forceActiveFocus(Qt.ActiveWindowFocusReason);
    }

    Binding {
        target: replyRow.modelInterface
        property: "hasPendingReply"
        value: replyTextField.text !== ""
    }
    PlasmaComponents3.TextField {
        id: replyTextField
        Layout.fillWidth: true
        placeholderText: replyRow.modelInterface.replyPlaceholderText
                         || i18ndc("plasma_applet_org.kde.plasma.notifications", "Text field placeholder", "Type a reply…")
        Accessible.name: placeholderText
        // Plasma Fusion: in a banner, the keyboard focus arriving in the field starts the reply,
        // as a click on the field does. Without it Tab would put text into a banner that is not
        // replying, and Escape would then dismiss it with its draft. The history is left as it is.
        onActiveFocusChanged: {
            if (activeFocus && !replyRow.modelInterface.inHistory && !replyRow.modelInterface.replying) {
                replyRow.beginReplyRequested();
            }
        }
        onAccepted: {
            if (replyButton.enabled) {
                replyRow.modelInterface.replied(text);
            }
        }

        // Catches mouse click when reply field is already shown to start a reply
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.IBeamCursor
            visible: !replyRow.modelInterface.replying
            Accessible.name: "begin reply"
            Accessible.role: Accessible.Button
            Accessible.onPressAction: replyRow.beginReplyRequested()
            onClicked: mouse => {
                mouse.accepted = true
                replyRow.beginReplyRequested()
            }
        }
    }

    PlasmaComponents3.Button {
        id: replyButton
        icon.name: replyRow.modelInterface.replySubmitButtonIconName || (mirrored ? "document-send-rtl" : "document-send")
        text: replyRow.modelInterface.replySubmitButtonText
              || i18ndc("plasma_applet_org.kde.plasma.notifications", "@action:button", "Send")
        enabled: replyTextField.length > 0
        onClicked: replyRow.modelInterface.replied(replyTextField.text)
    }
}
