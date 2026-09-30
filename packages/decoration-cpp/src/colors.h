/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/
#pragma once

#include <QColor>

namespace KDecoration3
{
class DecoratedWindow;
}

namespace PlasmaFusion
{

// #d9434b: close button (Windows.dc.html:42, Colors.dc.html)
inline const QColor s_closeRed(217, 67, 75);

// Colours of one window, from its colour scheme (Header group = title bar, Window background,
// Selection background = accent) plus the board constants for the fills.
struct Colors {
    bool dark = true;
    QColor titleActive, titleInactive; // [Colors:Header] BackgroundNormal (active / inactive)
    QColor textActive, textInactive; // [Colors:Header] ForegroundNormal (active / inactive)
    QColor windowActive, windowInactive; // [Colors:Window] BackgroundNormal: under the 1 px edge
    QColor tint; // board fills: white on dark schemes, ink #141827 on light ones
    QColor accent; // [Colors:Selection] BackgroundNormal: hovered buttons
    QColor accentRing; // 3 px ring around a hovered button: DecorationHover (#5b9dff) at 30 %
    QColor glyphActive, glyphInactive;
    QColor dot; // left layout: plain circles at rest
    qreal dotInactiveOpacity = 0.4;
    qreal fillActive = 0.10; // neutral button fill (tint opacity)
    qreal fillInactive = 0.07;
    qreal fillDisabled = 0.05;
    QColor shadow;
    qreal shadowActiveOpacity = 0.55;
    qreal shadowInactiveOpacity = 0.35;

    static Colors fromWindow(const KDecoration3::DecoratedWindow *window);

    QColor edge(bool active) const; // the 1 px outline, opaque (board border over the window)
};

QColor mix(const QColor &a, const QColor &b, qreal t); // RGBA interpolation, t = 0 -> a
QColor withAlpha(const QColor &c, qreal alpha);

} // namespace PlasmaFusion
