// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Shapes

// A line icon of the Plasma Fusion boards: an SVG path on a 24 x 24 grid, stroked 1.8.
Item {
    id: icon

    property string path: ""
    property color color: "#e8ebf4"
    property real size: 16
    property real strokeWidth: 1.8

    implicitWidth: size
    implicitHeight: size

    Shape {
        width: 24
        height: 24
        scale: icon.size / 24
        transformOrigin: Item.TopLeft
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: icon.path.length > 0 ? icon.color : "transparent"
            strokeWidth: icon.strokeWidth
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: icon.path.length > 0 ? icon.path : "M0 0" }
        }
    }
}
