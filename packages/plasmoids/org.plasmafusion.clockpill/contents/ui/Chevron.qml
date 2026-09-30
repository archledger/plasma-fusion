/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Shapes

// The boards' 16 px chevron (24 px grid path "M15 6l-6 6 6 6", stroke 1.8, round caps),
// drawn at `size` (16 px on the board): the path below is on the 16 px grid (every coordinate
// and the stroke scaled by 2/3) and is scaled to the size.
Shape {
    id: chevron

    property color color: "#a3abc2"
    // Points left by default; `next` points right.
    property bool next: false
    property real size: 16

    implicitWidth: size
    implicitHeight: size
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        strokeColor: chevron.color
        strokeWidth: 1.2 * chevron.size / 16
        scale: Qt.size(chevron.size / 16, chevron.size / 16)
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        PathSvg {
            path: chevron.next ? "M 6 4 L 10 8 L 6 12" : "M 10 4 L 6 8 L 10 12"
        }
    }
}
