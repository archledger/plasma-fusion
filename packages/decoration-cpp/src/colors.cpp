/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/
#include "colors.h"

#include <KDecoration3/DecoratedWindow>

#include <KColorScheme>

#include <QPalette>

namespace PlasmaFusion
{

using KDecoration3::ColorGroup;
using KDecoration3::ColorRole;

namespace
{
const QColor s_ink(20, 24, 39); // #141827, light-scheme text; light boards tint with rgba(20,24,39,a)

QColor valid(const QColor &c, const QColor &fallback)
{
    return c.isValid() ? c : fallback;
}

// The 3 px ring of a hovered button is the scheme's DecorationHover (#5b9dff next to the #2f6fdf
// accent, Windows.dc.html:108) at 30 %. A window whose accent differs from the global one (its own
// colour scheme) gets a lighter, more saturated version of its accent instead.
QColor hoverColor(const QColor &accent)
{
    const KColorScheme selection(QPalette::Active, KColorScheme::Selection);
    if (selection.background().color().rgb() == accent.rgb()) {
        const QColor hover = selection.decoration(KColorScheme::HoverColor).color();
        if (hover.isValid()) {
            return hover;
        }
    }
    float h, s, l, a;
    accent.getHslF(&h, &s, &l, &a);
    return QColor::fromHslF(h < 0 ? 0 : h, qMin(1.0f, s * 1.35f), qMin(0.85f, l + 0.15f));
}
} // namespace

QColor mix(const QColor &a, const QColor &b, qreal t)
{
    if (t <= 0) {
        return a;
    }
    if (t >= 1) {
        return b;
    }
    return QColor::fromRgbF(a.redF() + (b.redF() - a.redF()) * t,
                            a.greenF() + (b.greenF() - a.greenF()) * t,
                            a.blueF() + (b.blueF() - a.blueF()) * t,
                            a.alphaF() + (b.alphaF() - a.alphaF()) * t);
}

QColor withAlpha(const QColor &c, qreal alpha)
{
    QColor r(c);
    r.setAlphaF(qBound(0.0, c.alphaF() * alpha, 1.0));
    return r;
}

Colors Colors::fromWindow(const KDecoration3::DecoratedWindow *window)
{
    Colors c;
    const QPalette palette = window ? window->palette() : QPalette();
    if (window) {
        c.titleActive = window->color(ColorGroup::Active, ColorRole::TitleBar);
        c.titleInactive = window->color(ColorGroup::Inactive, ColorRole::TitleBar);
        c.textActive = window->color(ColorGroup::Active, ColorRole::Foreground);
        c.textInactive = window->color(ColorGroup::Inactive, ColorRole::Foreground);
    }
    // Colors.dc.html defaults (Plasma Fusion Dark) for anything the scheme leaves out
    c.titleActive = valid(c.titleActive, QColor(34, 40, 64));
    c.titleInactive = valid(c.titleInactive, c.titleActive);
    c.textActive = valid(c.textActive, QColor(232, 235, 244));
    c.textInactive = valid(c.textInactive, c.textActive);
    c.windowActive = valid(palette.color(QPalette::Active, QPalette::Window), c.titleActive);
    c.windowInactive = valid(palette.color(QPalette::Inactive, QPalette::Window), c.windowActive);
    c.accent = valid(palette.color(QPalette::Active, QPalette::Highlight), QColor(47, 111, 223));
    c.accent.setAlpha(255);

    c.dark = qGray(c.titleActive.rgb()) < 128;
    c.accentRing = withAlpha(hoverColor(c.accent), 0.30);
    c.glyphActive = c.textActive;
    if (c.dark) {
        // Main.dc.html:94-96, 145-147; Windows.dc.html:120, spec 6
        c.tint = Qt::white;
        c.glyphInactive = QColor(163, 171, 194); // #a3abc2
        c.dot = QColor(136, 145, 170); // #8891aa
        c.dotInactiveOpacity = 0.40;
        c.fillActive = 0.10;
        c.fillInactive = 0.07;
        c.fillDisabled = 0.05;
        c.shadow = Qt::black;
        c.shadowActiveOpacity = 0.55;
        c.shadowInactiveOpacity = 0.35;
    } else {
        // MainLight.dc.html:76, 94-96, 138, 145-147
        c.tint = s_ink;
        c.glyphInactive = QColor(91, 98, 120); // #5b6278
        c.dot = QColor(154, 160, 178); // #9aa0b2
        c.dotInactiveOpacity = 0.45;
        c.fillActive = 0.10;
        c.fillInactive = 0.07;
        c.fillDisabled = 0.04;
        c.shadow = s_ink;
        c.shadowActiveOpacity = 0.22;
        c.shadowInactiveOpacity = 0.14;
    }
    return c;
}

QColor Colors::edge(bool active) const
{
    // Windows.dc.html spec 5: 1 px white line at 12-14 %: 0.14 active, 0.08 inactive (Main.dc.html:76),
    // drawn over the window background like the CSS border, so it is opaque.
    const QColor base = active ? windowActive : windowInactive;
    QColor e = mix(QColor(base.red(), base.green(), base.blue()), tint, active ? 0.14 : 0.08);
    e.setAlpha(255);
    return e;
}

} // namespace PlasmaFusion
