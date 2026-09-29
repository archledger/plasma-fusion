/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Shapes

// A line icon from the design: a 24x24 SVG path stroked at 1.8 units with round caps and joins
// (svg.i in the boards), drawn at `size` px.
Shape {
    id: glyph

    property string path
    property color color: "white"
    property real size: 24

    width: size
    height: size
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        strokeColor: glyph.color
        strokeWidth: 1.8 * glyph.size / 24
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        scale: Qt.size(glyph.size / 24, glyph.size / 24)

        PathSvg {
            path: glyph.path
        }
    }
}
