// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

pragma Singleton

import QtQuick

// Plasma Fusion lock screen tokens: the Lock and Login boards' colours, fonts, sizes and
// line-icon paths (24 x 24 grid, drawn with a 1.8 px stroke), plus date/time helpers.
QtObject {
    // Fonts. Manrope for UI text, Space Grotesk for the clock and the user name.
    readonly property string uiFont: "Manrope"
    readonly property string displayFont: "Space Grotesk"
    // Bold (700) and extra bold (800) text. Both fonts are variable fonts whose default
    // instance is light, and Qt's FreeType engine synthesises bold on top of any weight of
    // 700 or more below 64 px in that case, so Font.Bold would come out heavier than the
    // real ExtraBold. Text therefore asks for the named instance by style name and keeps
    // the weight at DemiBold (also the fallback for any other font).
    readonly property string bold: "Bold"
    readonly property string extraBold: "ExtraBold"

    // Text colours on the dark glass.
    readonly property color text: "#e8ebf4"
    readonly property color textSecondary: "#b8bfd3"
    readonly property color textTertiary: "#a3abc2"
    readonly property color textMuted: "#cdd3e4"
    readonly property color placeholder: "#8f98b3"
    readonly property color link: "#8ab8ff"
    readonly property color warning: "#f2c38a"
    readonly property color error: "#ff9b9f"

    // Accent (Login board: focus border, focus halo, unlock button).
    readonly property color accent: "#5b9dff"
    readonly property color accentHalo: Qt.rgba(91 / 255, 157 / 255, 1, 0.2)
    readonly property color accentStrong: "#2f6fdf"
    readonly property color accentStrongHover: "#3d7cea"
    readonly property color textOnAccent: "#ffffff"
    // Keyboard focus ring (Controls board, dark scheme: 2 px #8ab8ff, 2 px gap).
    readonly property color focusRing: "#8ab8ff"

    // Glass surfaces (Lock board).
    readonly property color glassFill: Qt.rgba(14 / 255, 18 / 255, 34 / 255, 0.6)
    readonly property color glassFillPill: Qt.rgba(14 / 255, 18 / 255, 34 / 255, 0.55)
    readonly property color glassBorder: Qt.rgba(1, 1, 1, 0.1)
    readonly property color glassBorderPill: Qt.rgba(1, 1, 1, 0.14)
    readonly property color glassFillSoftware: Qt.rgba(14 / 255, 18 / 255, 34 / 255, 0.78)

    // Login board chips, fields and round buttons.
    readonly property color fieldFill: Qt.rgba(1, 1, 1, 0.1)
    readonly property color fieldBorder: Qt.rgba(1, 1, 1, 0.16)
    readonly property color chipFill: Qt.rgba(1, 1, 1, 0.08)
    readonly property color chipFillHover: Qt.rgba(1, 1, 1, 0.16)
    readonly property color chipBorder: Qt.rgba(1, 1, 1, 0.12)
    readonly property color layoutBadgeBorder: Qt.rgba(1, 1, 1, 0.25)
    readonly property color avatarFill: "#7b5cd6"
    readonly property color avatarRing: Qt.rgba(1, 1, 1, 0.14)
    readonly property color playFill: "#e8ebf4"
    readonly property color playGlyph: "#1b2031"
    readonly property color shadow: Qt.rgba(0, 0, 0, 0.4)

    // Wallpaper dimming: Lock board (idle) and Login board (prompt shown).
    readonly property color dimIdle: Qt.rgba(8 / 255, 10 / 255, 22 / 255, 0.22)
    readonly property color dimActive: Qt.rgba(8 / 255, 11 / 255, 24 / 255, 0.5)
    readonly property color fallbackBackground: "#141a2e"

    // Board geometry (1440 x 900 board; vertical positions scale with the screen height).
    readonly property real boardHeight: 900
    readonly property int edge: 32

    // Line icons.
    readonly property string iconLock: "M7 11h10a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2v-6a2 2 0 0 1 2-2zM8 11V8a4 4 0 0 1 8 0v3"
    readonly property string iconUnlock: "M7 11h10a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2v-6a2 2 0 0 1 2-2zM8 11V8a4 4 0 0 1 7.6-1.8"
    readonly property string iconWifiArc3: "M2 9a15 15 0 0 1 20 0"
    readonly property string iconWifiArc2: "M5 12.5a10 10 0 0 1 14 0"
    readonly property string iconWifiArc1: "M8.5 16a5 5 0 0 1 7 0"
    readonly property string iconWifiDot: "M12 19.5h.01"
    readonly property string iconSlash: "M4 4l16 16"
    readonly property string iconWired: "M6 8h12v9H6zM9.5 8V5.5h5V8M9 17v-3M12 17v-3M15 17v-3"
    readonly property string iconBattery: "M4 7h14a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V9a2 2 0 0 1 2-2zM22 11v2"
    readonly property string iconBolt: "M12.2 8.6 8.9 12.6h2.6l-.9 2.8 3.4-4.1h-2.6z"
    readonly property string iconEye: "M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7S2 12 2 12zM9 12a3 3 0 1 0 6 0a3 3 0 1 0-6 0"
    readonly property string iconArrowRight: "M5 12h14M13 6l6 6-6 6"
    readonly property string iconArrowLeft: "M19 12H5M11 6l-6 6 6 6"
    readonly property string iconCapsLock: "M12 4l7 8h-4v7H9v-7H5z"
    readonly property string iconSleep: "M20 14.5A8 8 0 1 1 9.5 4a6.5 6.5 0 0 0 10.5 10.5z"
    readonly property string iconHibernate: "M12 3v18M4.2 7.5l15.6 9M4.2 16.5l15.6-9M9.6 4.6 12 6l2.4-1.4M9.6 19.4 12 18l2.4 1.4"
    readonly property string iconSwitchUser: "M6.6 8.6a2.9 2.9 0 1 0 5.8 0a2.9 2.9 0 1 0-5.8 0M2.8 19a6.7 6.7 0 0 1 13.4 0M15.6 5.9a2.9 2.9 0 0 1 0 5.4M18.4 13.8a6.7 6.7 0 0 1 2.8 5.2"
    readonly property string iconKeyboard: "M4 6h16a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2zM6.5 10h.01M10 10h.01M14 10h.01M17.5 10h.01M8 14h8"
    readonly property string iconBell: "M6 16V11a6 6 0 0 1 12 0v5l1.5 2h-15zM10 20.5a2 2 0 0 0 4 0"
    // Filled glyphs.
    readonly property string glyphPlay: "M8 5l11 7-11 7z"
    readonly property string glyphPause: "M7 5h3.5v14H7zM13.5 5H17v14h-3.5z"
    readonly property string glyphPrevious: "M17.5 6v12L9 12zM6.5 6h2v12h-2z"
    readonly property string glyphNext: "M6.5 6v12L15 12zM15.5 6h2v12h-2z"

    // Battery fill rectangle for a level in percent (inside iconBattery).
    function batteryFill(percent) {
        const w = Math.max(1, Math.min(11, 11 * percent / 100));
        return "M5 10h" + w.toFixed(2) + "v4H5z";
    }

    // The locale's long date without the year: "Monday, 28 September" (en_GB),
    // "Monday, September 28" (en_US), "Montag, 28. September" (de).
    function dateFormatWithoutYear(locale) {
        let f = locale.dateFormat(Locale.LongFormat);
        const yearAtEnd = /[\s,.\/-]*y+(\s*'[^']*')?[年년]?[\s,.\/-]*$/;
        const yearAtStart = /^y+[年년.\/-]?\s*/;
        const yearInside = /[\s,]*y+(\s*'[^']*')?[年년]?[\s,]*/;
        if (yearAtEnd.test(f)) {
            f = f.replace(yearAtEnd, "");
        } else if (yearAtStart.test(f)) {
            f = f.replace(yearAtStart, "");
        } else {
            f = f.replace(yearInside, " ");
        }
        f = f.replace(/[\s,]+$/, "").trim();
        return f.length > 0 ? f : "dddd, d MMMM";
    }

    // Splits the locale's short time into the main part and the AM/PM marker, so that the
    // marker can be drawn smaller ("2:49" + "PM"); 24-hour locales get no marker.
    function timeParts(locale, dateTime) {
        const f = locale.timeFormat(Locale.ShortFormat).replace(/:ss?/, "");
        const token = f.match(/[aA][pP]?/);
        const full = locale.toString(dateTime, f);
        if (!token) {
            return { main: full, suffix: "" };
        }
        const suffix = locale.toString(dateTime, token[0]);
        const at = full.indexOf(suffix);
        const main = at < 0 ? full : (full.slice(0, at) + full.slice(at + suffix.length));
        return { main: main.replace(/[\s\u202f\u00a0]+/g, " ").trim(), suffix: suffix };
    }
}
