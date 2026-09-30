/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import org.kde.kirigami as Kirigami

// Text in the design's type scale: size in board pixels and CSS weight (400-800).
// Plasma Fusion installs Manrope and Space Grotesk as one static file per weight (the build's
// fonts/*/static), so the CSS weight is the font weight: Qt picks the matching file and draws
// no synthetic bold (it only emboldens files lighter than 700). When the family is not
// installed the Plasma UI font is used with the same weight.
Text {
    id: label

    // Wanted family; "" means the Plasma UI font.
    property string family: "Manrope"
    property real px: 13
    property int weight: 400

    readonly property bool installed: family !== "" && Qt.fontFamilies().indexOf(family) !== -1

    font.family: installed ? family : Kirigami.Theme.defaultFont.family
    font.pixelSize: px
    font.weight: weight
    textFormat: Text.PlainText
    verticalAlignment: Text.AlignVCenter
}
