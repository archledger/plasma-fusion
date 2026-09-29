// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
// Offscreen test stand-in for KWin.DesktopBackground (test use only): a flat wallpaper colour.
import QtQuick

Rectangle {
    property var output
    property var desktop
    property string activity
    property string outputName
    color: "#2e3d73"
}
