// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// Line icons of the Plasma Fusion design (24 x 24 grid, drawn with a 1.8 stroke,
// round caps and joins). Path data copied from the design boards.

.pragma library

var wifiArc1 = "M2 9a15 15 0 0 1 20 0";
var wifiArc2 = "M5 12.5a10 10 0 0 1 14 0";
var wifiArc3 = "M8.5 16a5 5 0 0 1 7 0";
var wifiDot = "M12 19.5h.01";
var wifi = wifiArc1 + wifiArc2 + wifiArc3 + wifiDot;
var slash = "M4 4l16 16";

var speaker = "M4 9h4l5-4v14l-5-4H4z";
var wave1 = "M16 9a4 4 0 0 1 0 6";
var wave2 = "M18.5 6.5a8 8 0 0 1 0 11";
var muteCross = "M16 9l5 6M21 9l-5 6";

var batteryOutline = "M4 7h14a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V9a2 2 0 0 1 2-2zM22 11v2";
var batteryBolt = "M12.5 7.5L8 12.8h3.2L9.8 16.5 14.6 11h-3.2z";
function batteryLevel(width) {
    return "M5 10h" + width.toFixed(2) + "v4H5z";
}

var bell = "M6 16V11a6 6 0 0 1 12 0v5l2 2H4zM10 20a2 2 0 0 0 4 0";
var bellOff = bell + "M4 4l16 16";
var phone = "M8 3h8a1 1 0 0 1 1 1v16a1 1 0 0 1-1 1H8a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1zM11 18h2";
var clipboard = "M9 4h6v3H9zM7 5.5H6a1 1 0 0 0-1 1V20a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1V6.5a1 1 0 0 0-1-1h-1";
var screenshot = "M4 8V5a1 1 0 0 1 1-1h3M16 4h3a1 1 0 0 1 1 1v3M20 16v3a1 1 0 0 1-1 1h-3M8 20H5a1 1 0 0 1-1-1v-3";
var settings = "M9 12a3 3 0 1 0 6 0a3 3 0 1 0-6 0M12 2.5v3M12 18.5v3M2.5 12h3M18.5 12h3M5.3 5.3l2.1 2.1M16.6 16.6l2.1 2.1M5.3 18.7l2.1-2.1M16.6 7.4l2.1-2.1";
var settingsSmall = "M9 12a3 3 0 1 0 6 0a3 3 0 1 0-6 0M12 2.5v3M12 18.5v3M2.5 12h3M18.5 12h3";
var lock = "M7 11h10a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2v-6a2 2 0 0 1 2-2zM8 11V8a4 4 0 0 1 8 0v3";
var power = "M12 3v9M6.3 6.3a8 8 0 1 0 11.4 0";
var chevronRight = "M9 6l6 6-6 6";
var chevronLeft = "M15 6l-6 6 6 6";
var close = "M7 7l10 10M17 7L7 17";
var brightness = "M8 12a4 4 0 1 0 8 0a4 4 0 1 0-8 0M12 2v2M12 20v2M2 12h2M20 12h2M5 5l1.5 1.5M17.5 17.5L19 19M5 19l1.5-1.5M17.5 6.5L19 5";
var bluetooth = "M7 7l10 10-5 4V3l5 4L7 17";
var moon = "M20 14.5A8 8 0 1 1 9.5 4a6.5 6.5 0 0 0 10.5 10.5z";
var gauge = "M4 16a8 8 0 0 1 16 0M12 16l4-5";
// Disks & Devices: a USB stick (body, connector, contacts) and the eject mark.
var usbDrive = "M8 10h8v10a1 1 0 0 1-1 1H9a1 1 0 0 1-1-1zM9.5 4h5v6h-5zM11 6.5h.01M13 6.5h.01";
var eject = "M12 5l7 8H5zM5 18.5h14";
var coffee = "M4 8h12v6a6 6 0 0 1-12 0zM16 9h2a3 3 0 0 1 0 6h-2M3 21h15M7 2v3M12 2v3";
var contrast = "M3 12a9 9 0 1 0 18 0a9 9 0 1 0-18 0M12 3v18";
var contrastFill = "M12 3a9 9 0 0 1 0 18z";
var previous = "M18 6l-8 6 8 6zM6 6v12";
var next = "M6 6l8 6-8 6zM18 6v12";
var play = "M8 5l11 7-11 7z";
var pause = "M9 6v12M15 6v12";
var pauseFill = "M7.5 5.5h3v13h-3zM13.5 5.5h3v13h-3z";
var keyboard = "M3 7h18v10H3zM7 11h.01M11 11h.01M15 11h.01M8 14h8";
var more = "M5 12h.01M12 12h.01M19 12h.01";
var wired = "M9 3h6v5H9zM12 8v5M6 13h12M6 13v4M18 13v4M4 17h4v4H4zM16 17h4v4h-4z";
var airplane = "M12 3c1 0 1.5 1 1.5 2v4.5L21 14v2l-7.5-2.5V18l2 1.5V21L12 20l-3.5 1v-1.5l2-1.5v-4.5L3 16v-2l7.5-4.5V5c0-1 .5-2 1.5-2z";
var plus = "M12 5v14M5 12h14";
var headphones = "M4 15v-3a8 8 0 0 1 16 0v3M4 15a2 2 0 0 1 2-2h1v7H6a2 2 0 0 1-2-2zM20 15a2 2 0 0 0-2-2h-1v7h1a2 2 0 0 0 2-2z";
var microphone = "M9 4a3 3 0 0 1 6 0v8a3 3 0 0 1-6 0zM6 10v2a6 6 0 0 0 12 0v-2M12 18v4M8 22h8";
var check = "M5 12.5l4.5 4.5L19 7.5";

// Tablet row and tile (TABLET 4.6).
var rotate = "M20 12a8 8 0 1 1-2.34-5.66M20 4v5h-5";
var fullscreen = "M14 4h6v6M10 20H4v-6M20 4l-6.5 6.5M4 20l6.5-6.5";
// A swipe up from the bottom edge (the gesture lock, TABLET2 G1).
var swipeUp = "M12 16V5M7.5 9.5L12 5l4.5 4.5M6 20h12";
var pen = "M4 20l4.2-1 11-11a2.1 2.1 0 0 0-3-3l-11 11zM14.5 6.5l3 3";
var tablet = "M6 3h12a1 1 0 0 1 1 1v16a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1zM11 18h2";
