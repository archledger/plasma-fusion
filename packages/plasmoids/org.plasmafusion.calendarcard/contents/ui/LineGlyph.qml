/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Shapes

// A line icon as on the boards (`svg.i`: 24 x 24 view box, 1.8 stroke, round caps and joins,
// no fill), drawn at `size` px. Shared by the three card widgets (identical copies).
Item {
    id: glyph

    // SVG path data in the 24 x 24 view box.
    property string path
    property color color: "white"
    property real size: 16
    property real strokeWidth: 1.8

    implicitWidth: size
    implicitHeight: size

    Shape {
        width: 24
        height: 24
        anchors.centerIn: parent
        scale: glyph.size / 24
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: "transparent"
            strokeColor: glyph.color
            strokeWidth: glyph.strokeWidth
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: glyph.path }
        }
    }
}
