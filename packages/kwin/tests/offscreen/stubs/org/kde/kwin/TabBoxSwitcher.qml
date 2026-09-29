// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
// Offscreen test stand-in for KWin's TabBoxSwitcher (test use only).
import QtQuick

QtObject {
    default property QtObject item
    property var model
    property rect screenGeometry: Qt.rect(0, 0, 1440, 900)
    property bool visible: false
    property bool allDesktops: false
    property int currentIndex: 0
    property bool noModifierGrab: false
    property bool compositing: true
    property bool automaticallyHide: true
    signal aboutToShow()
    signal aboutToHide()
}
