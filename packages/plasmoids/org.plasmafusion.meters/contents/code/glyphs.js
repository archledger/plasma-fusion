// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// Line glyphs of the system meters, drawn for the Icons board's grid (24 x 24, a 1.8 stroke with
// round caps and joins; LineIcon.qml). The board has no meter glyphs: these follow its Download
// arrow and the status pill's simple outlines.

.pragma library

// A processor: the chip, its die and two pins on each side.
var cpu = "M7 7h10v10H7zM10 10h4v4h-4zM10 3.5V7M14 3.5V7M10 17v3.5M14 17v3.5M3.5 10H7M3.5 14H7M17 10h3.5M17 14h3.5";
// A memory module: the board, three chips and the contacts.
var memory = "M3 7h18v9H3zM7 10.5v2.5M12 10.5v2.5M17 10.5v2.5M6 16v3M10 16v3M14 16v3M18 16v3";
// The board's Download arrow without its base line, and the same arrow upwards.
var download = "M12 4v14M7 13l5 5 5-5";
var upload = "M12 20V6M7 11l5-5 5 5";
// A thermometer with its scale line.
var thermometer = "M10 14.5V5a2 2 0 0 1 4 0v9.5a4 4 0 1 1-4 0zM12 9v8.5";
// The quick settings' power-mode gauge: the widget with every meter turned off.
var gauge = "M4 16a8 8 0 0 1 16 0M12 16l4-5";
