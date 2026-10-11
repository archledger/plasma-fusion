// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
// Offscreen test stand-in for KWin's custom (Meta+T) root tile (test use only): its string names
// the class, as KWin's does ("KWin::RootTile(0x…)").
import QtQuick

QtObject {
    property var parent: null
    property var tiles: []
    property real padding: 6
}
