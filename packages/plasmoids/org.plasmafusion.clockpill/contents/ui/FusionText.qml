/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import org.kde.kirigami as Kirigami

// Text in the design's type scale: size in board pixels and CSS weight (400-800).
// Manrope and Space Grotesk are variable fonts. Qt adds a synthetic bold on top of their named
// Bold/ExtraBold instances, so for them the weight goes on the "wght" axis and the font weight
// stays Normal. When the family is not installed the Plasma UI font is used with a plain weight.
Text {
    id: label

    // Wanted family; "" means the Plasma UI font.
    property string family: "Manrope"
    property real px: 13
    property int weight: 400

    readonly property bool installed: family !== "" && Qt.fontFamilies().indexOf(family) !== -1
    readonly property bool variableWeight: installed && (family === "Manrope" || family === "Space Grotesk")

    font.family: installed ? family : Kirigami.Theme.defaultFont.family
    font.pixelSize: px
    font.weight: variableWeight ? Font.Normal : weight
    font.variableAxes: variableWeight ? { "wght": weight } : ({})
    textFormat: Text.PlainText
    verticalAlignment: Text.AlignVCenter
}
