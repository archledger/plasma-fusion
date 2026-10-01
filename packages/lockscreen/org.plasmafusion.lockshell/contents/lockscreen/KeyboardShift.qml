/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.workspace.keyboardlayout as Keyboards

// The on-screen keyboard on the lock screen (Wayland: KWin's input method shows it): whether it is
// up, and moving the prompt above it. Plasma 6.7 did this in org.kde.breeze.components'
// VirtualKeyboardLoader, which Plasma 6.8 removed (its lock screen now leaves the prompt where it
// is); without it this lock shell failed to load on 6.8 ("VirtualKeyboardLoader is not a type")
// and the greeter fell back to its built-in locker (PLASMA-68). Same movement as 6.7's: the prompt
// rises just enough for mainBlock's visibleBoundary to clear the keyboard.
Item {
    id: shift

    required property Item screenRoot
    required property Item mainStack
    required property Item mainBlock

    readonly property bool keyboardActive: Keyboards.KWinVirtualKeyboard.visible
    readonly property real keyboardHeight: keyboardActive ? Qt.inputMethod.keyboardRectangle.height : 0
    readonly property real stackY: keyboardActive && keyboardHeight > 0
        ? Math.min(0, screenRoot.height - keyboardHeight - mainBlock.visibleBoundary) : 0

    // Shows or hides KWin's keyboard (the lock screen's keyboard button; Wayland only).
    function showHide(): void {
        Keyboards.KWinVirtualKeyboard.active = !keyboardActive;
    }

    onStackYChanged: {
        move.to = stackY;
        move.restart();
    }
    NumberAnimation {
        id: move
        target: shift.mainStack
        property: "y"
        duration: Kirigami.Units.longDuration
        easing.type: Easing.InOutQuad
    }
}
