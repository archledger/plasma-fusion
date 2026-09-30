// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
// Test-only probe (generators/plasma-style/tests): shows the area the panel containment gives an
// applet as a magenta block and prints "o1st-probe" lines with its geometry in the panel window.
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid

PlasmoidItem {
    id: root
    preferredRepresentation: fullRepresentation
    fullRepresentation: Rectangle {
        id: box
        color: "#ff00ff"
        Layout.preferredWidth: 40
        Layout.preferredHeight: 40
        Layout.minimumWidth: 40
        Layout.minimumHeight: 12
        function report() {
            const p = box.mapToItem(null, 0, 0);
            const w = box.Window.window;
            console.warn("o1st-probe", Plasmoid.location, "x", Math.round(p.x), "y", Math.round(p.y),
                        "w", Math.round(box.width), "h", Math.round(box.height),
                        "window", w ? w.width + "x" + w.height : "-",
                        "right", w ? Math.round(w.width - p.x - box.width) : "-");
        }
        Timer { id: later; interval: 500; onTriggered: box.report() }
        onWidthChanged: later.restart()
        onHeightChanged: later.restart()
        onXChanged: later.restart()
        Component.onCompleted: later.restart()
    }
}
