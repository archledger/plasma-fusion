// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Shapes

// A line icon on the boards' 24 x 24 grid: "path" is stroked in "color", "dimPath" in
// "dimColor" (inactive Wi-Fi arcs), "fillPath" is filled with "fillColor" and "overlayPath"
// is filled with "overlayColor" on top (charging bolt).
Item {
    id: icon

    property string path: ""
    property string dimPath: ""
    property string fillPath: ""
    property string overlayPath: ""
    property color color: PfStyle.text
    property color dimColor: Qt.rgba(color.r, color.g, color.b, 0.3)
    property color fillColor: color
    property color overlayColor: PfStyle.playGlyph
    property real size: 18
    property real strokeWidth: 1.8

    implicitWidth: size
    implicitHeight: size
    width: size
    height: size

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
            strokeColor: "transparent"
            strokeWidth: 0
            fillColor: icon.fillPath.length > 0 ? icon.fillColor : "transparent"
            PathSvg { path: icon.fillPath.length > 0 ? icon.fillPath : "M0 0" }
        }
        ShapePath {
            strokeColor: "transparent"
            strokeWidth: 0
            fillColor: icon.overlayPath.length > 0 ? icon.overlayColor : "transparent"
            PathSvg { path: icon.overlayPath.length > 0 ? icon.overlayPath : "M0 0" }
        }
    }
}
