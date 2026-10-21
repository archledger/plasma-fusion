/* SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
 * SPDX-License-Identifier: GPL-2.0-or-later
 *
 * Qt's virtual keyboard inside the theme's scene. SDDM's default InputMethod=qtvirtualkeyboard
 * (Configuration.h; Debian keeps it, Ubuntu and KDE neon set it) starts the greeter with
 * QT_IM_MODULE=qtvirtualkeyboard. With no InputPanel in the scene, Qt opens a keyboard window of
 * its own over the lower half of the screen whenever a text field has focus - at once, since the
 * password field starts focused - covering the user row, the session pill and the power buttons
 * (Debian testing, 2026-10-21). In the scene it shows only after the on-screen keyboard button,
 * and only while Qt's input method asks for a keyboard, as KDE's Breeze theme does.
 *
 * Main.qml creates this file itself, and only on an X11 greeter (a Wayland greeter's keyboard is
 * the compositor's): without QtQuick.VirtualKeyboard it gets an error status and hides the button.
 */

import QtQuick 2.15
import QtQuick.VirtualKeyboard

InputPanel {
    // Set by the on-screen keyboard button; Main.qml clears it when the keyboard goes
    property bool activated: false
    // Qt's input method wants a keyboard (a text field has focus)
    property bool requested: Qt.inputMethod.visible
    // Qt's input method has asked for a keyboard at least once. Only Qt's virtual keyboard does
    // (it does at once: the password field starts focused); a greeter started with another input
    // method (SDDM's InputMethod empty) never does, and the button is not offered there.
    property bool available: false

    active: activated && requested
    visible: active
    onRequestedChanged: if (requested) available = true
    Component.onCompleted: available = requested
}
