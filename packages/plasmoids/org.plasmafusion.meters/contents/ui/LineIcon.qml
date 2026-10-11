// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Shapes

// A line icon on the design's 24 x 24 grid. "path" is stroked in "color",
// "dimPath" in "dimColor" (inactive signal bars and the like) and "fillPath"
// is filled with "fillColor" (battery level, play triangle).
Item {
    id: icon

    property string path: ""
    property string dimPath: ""
    property string fillPath: ""
    property color color: "#e8ebf4"
    property color dimColor: Qt.rgba(color.r, color.g, color.b, 0.28)
    property color fillColor: color
    property real size: 16
    property real strokeWidth: 1.8
    property bool fillStroked: false

    implicitWidth: size
    implicitHeight: size

    Shape {
        width: 24
        height: 24
        scale: icon.size / 24
        transformOrigin: Item.TopLeft
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: icon.dimPath.length > 0 ? icon.dimColor : "transparent"
            strokeWidth: icon.strokeWidth
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: icon.dimPath.length > 0 ? icon.dimPath : "M0 0" }
        }
        ShapePath {
            strokeColor: icon.path.length > 0 ? icon.color : "transparent"
            strokeWidth: icon.strokeWidth
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: icon.path.length > 0 ? icon.path : "M0 0" }
        }
        ShapePath {
            strokeColor: icon.fillStroked && icon.fillPath.length > 0 ? icon.fillColor : "transparent"
            strokeWidth: icon.fillStroked ? icon.strokeWidth : 0
            fillColor: icon.fillPath.length > 0 ? icon.fillColor : "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: icon.fillPath.length > 0 ? icon.fillPath : "M0 0" }
        }
    }
}
