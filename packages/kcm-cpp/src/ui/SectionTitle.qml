/*
    Section heading: 12 px ExtraBold, secondary colour (Main board "Style", "Accent color", ...).

    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2

QQC2.Label {
    required property FusionPalette pal

    // CSS line box of 12 px Manrope is 16.4 px; 16 keeps the sections on the board's rows.
    Layout.preferredHeight: 16
    verticalAlignment: Text.AlignTop
    font.family: pal.family
    font.pixelSize: 12
    font.weight: Font.ExtraBold
    color: pal.section
    Accessible.role: Accessible.Heading
}
