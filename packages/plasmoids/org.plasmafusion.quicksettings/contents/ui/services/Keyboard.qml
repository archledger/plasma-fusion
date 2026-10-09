// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import org.kde.plasma.workspace.keyboardlayout as Keyboards

// Current keyboard layout from KWin (org.kde.keyboard). The badge text is the
// layout's display name (kxkbrc [Layout] DisplayNames), else its short name.
Item {
    id: kbd

    readonly property var layouts: layout.layoutsList || []
    readonly property int count: layouts.length
    readonly property bool available: count > 0 && layout.layout >= 0 && layout.layout < count
    readonly property var current: available ? layouts[layout.layout] : null
    readonly property string label: current ? String(current.displayName || current.shortName || "").toUpperCase() : ""
    readonly property string longName: current ? String(current.longName || "") : ""

    readonly property int index: layout.layout
    function next() {
        layout.switchToNextLayout();
    }
    function previous() {
        layout.switchToPreviousLayout();
    }
    function select(i: int) {
        if (i >= 0 && i < count) {
            layout.layout = i;
        }
    }

    Keyboards.KeyboardLayout {
        id: layout
    }
}
