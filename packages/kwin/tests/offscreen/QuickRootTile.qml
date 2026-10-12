// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
// Offscreen test stand-in for KWin's quick-tile root (test use only): its string names the class,
// as KWin's does ("KWin::QuickRootTile(0x…)").
import QtQuick

QtObject {
    property var parent: null
    property var tiles: []
    property real padding: 6
}
