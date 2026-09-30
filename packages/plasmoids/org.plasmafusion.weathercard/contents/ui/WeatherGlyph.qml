/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick

// Condition glyph of the weather card in the board's line style. "cloud" is the board's own
// path (Main.dc.html, weather widget); the others are drawn in the same style and box.
LineGlyph {
    // sun, moon, sunCloud, moonCloud, cloud, rain, snow, storm, fog ("" = cloud)
    property string condition: "cloud"

    readonly property var paths: ({
        "cloud": "M7 18h10a4 4 0 0 0 0-8a6 6 0 0 0-11.5 1.5A3.3 3.3 0 0 0 7 18z",
        "sun": "M8 12a4 4 0 1 0 8 0a4 4 0 1 0-8 0M12 5.5V3.5M16.6 7.4l1.41-1.41M18.5 12h2M16.6 16.6l1.41 1.41"
               + "M12 18.5v2M7.4 16.6l-1.41 1.41M5.5 12h-2M7.4 7.4L5.99 5.99",
        "moon": "M20 14.5A8.5 8.5 0 1 1 9.5 4a6.6 6.6 0 0 0 10.5 10.5z",
        "sunCloud": "M5.1 20.4h8a3.2 3.2 0 0 0 0-6.4a4.8 4.8 0 0 0-9.2 1.2A2.64 2.64 0 0 0 5.1 20.4z"
                    + "M13.5 7.5a3 3 0 1 0 6 0a3 3 0 1 0-6 0M16.5 3.1V1.8M19.61 4.39l.92-.92M20.9 7.5h1.3"
                    + "M19.61 10.61l.92.92M16.5 11.9v1.3M13.39 10.61l-.92.92M12.1 7.5h-1.3M13.39 4.39l-.92-.92",
        "moonCloud": "M5.1 20.4h8a3.2 3.2 0 0 0 0-6.4a4.8 4.8 0 0 0-9.2 1.2A2.64 2.64 0 0 0 5.1 20.4z"
                     + "M21 9.6A4.6 4.6 0 1 1 14.6 3.2a3.6 3.6 0 0 0 6.4 6.4z",
        "rain": "M7 15h10a4 4 0 0 0 0-8a6 6 0 0 0-11.5 1.5A3.3 3.3 0 0 0 7 15z"
                + "M8.5 17.8l-1 2.7M12.5 17.8l-1 2.7M16.5 17.8l-1 2.7",
        "snow": "M7 15h10a4 4 0 0 0 0-8a6 6 0 0 0-11.5 1.5A3.3 3.3 0 0 0 7 15z"
                + "M8 18.2h.01M12 18.2h.01M16 18.2h.01M10 21.2h.01M14 21.2h.01",
        "storm": "M7 15h10a4 4 0 0 0 0-8a6 6 0 0 0-11.5 1.5A3.3 3.3 0 0 0 7 15z"
                 + "M13 16.5l-2.2 3.2h3.2l-2.2 3.2",
        "fog": "M7 15h10a4 4 0 0 0 0-8a6 6 0 0 0-11.5 1.5A3.3 3.3 0 0 0 7 15z"
               + "M5 18.5h14M7.5 21.5h9"
    })

    path: paths[condition] || paths["cloud"]
    strokeWidth: condition === "snow" ? 2 : 1.8
}
