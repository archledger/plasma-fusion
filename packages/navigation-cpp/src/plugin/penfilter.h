// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <QStringList>
#include <chrono>
#include <input.h>

namespace KWin
{

// Plasma Fusion (TABLET2 PEN-2): in tablet posture the pen acts like a finger, as on iPadOS,
// Android and Windows since 1709. On Linux a pen tip is a left mouse button for every app that does
// not take tablet input (Qt turns unhandled tablet events into mouse events), so a pen drag selects
// text or starts a rubber band, and Qt Quick's ScrollView and Kirigami's tablet-mode scroll bars do not
// scroll by pen at all (research round 2, F-pen section 0). While the tip is down this filter feeds
// KWin's own touch path instead, so focus, activation, popups and each app's touch scrolling work as
// for a finger. Exempt: drawing apps (they keep pressure and tilt), presses in the bottom gesture zone
// (the pen never starts a shell gesture), and laptop posture or the "like a mouse" setting.
class FusionPenFilter : public InputEventFilter
{
public:
    FusionPenFilter();
    ~FusionPenFilter() override;

    // Tablet posture with plasmafusionrc [Pen] TabletPen=finger (the default).
    void setActive(bool active);
    bool isActive() const;
    // Window classes or desktop file names that keep the pen as a pen.
    void setDrawingApps(const QStringList &apps);

    bool tabletToolTipEvent(TabletToolTipEvent *event) override;
    bool tabletToolAxisEvent(TabletToolAxisEvent *event) override;
    bool tabletToolProximityEvent(TabletToolProximityEvent *event) override;

    static QStringList defaultDrawingApps();

private:
    bool exempt(const QPointF &pos) const;
    void finish(std::chrono::microseconds time, InputDevice *device);

    bool m_active = false;
    bool m_converting = false;
    QStringList m_drawingApps;
};

} // namespace KWin
