// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
// KWin script for the private test session: put the "Cursor edges" window at a known frame
// geometry (360,240 720x400) so the pointer can be moved onto its edges and corners.
for (const w of workspace.windowList()) {
    if (w.caption.indexOf("Cursor edges") === 0) {
        w.frameGeometry = {x: 360, y: 240, width: 720, height: 400};
        print("pfv-place " + JSON.stringify({x: w.frameGeometry.x, y: w.frameGeometry.y,
                                             width: w.frameGeometry.width, height: w.frameGeometry.height}));
    }
}
