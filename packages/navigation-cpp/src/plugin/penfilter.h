// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <QElapsedTimer>
#include <QPointF>
#include <QStringList>
#include <QTimer>
#include <chrono>
#include <functional>
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
//
// Press and hold (TABLET2 PEN-2 follow-up, as Windows Ink): a finger's long press opens no context
// menu in QtWidgets and XWayland apps, so with the pen as a finger they had none. When the tip rests
// 500 ms within 10 px, the emulated touch is cancelled, the rest of the stroke is swallowed, and a
// right click is sent at the press point when the pen lifts, as with Windows Ink
// (plasmafusionrc [Pen] TabletPenHold, default true).
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
    // Press and hold for a right click.
    void setRightClickOnHold(bool enabled);
    // A pen tap on the bottom zone (the home handle): the dock shows (research F-pen 4.14, so pen-only
    // use can leave an app; the pen still never makes a navigation gesture).
    void setBottomTapHandler(std::function<void()> handler);

    bool tabletToolTipEvent(TabletToolTipEvent *event) override;
    bool tabletToolAxisEvent(TabletToolAxisEvent *event) override;
    bool tabletToolProximityEvent(TabletToolProximityEvent *event) override;

    static QStringList defaultDrawingApps();

private:
    bool exempt(const QPointF &pos) const;
    bool shellLongPress(const QPointF &pos) const;
    bool inBottomZone(const QPointF &pos) const;
    void finish(std::chrono::microseconds time, InputDevice *device);
    void holdTimeout();

    bool m_active = false;
    bool m_converting = false;
    QStringList m_drawingApps;
    bool m_rightClickOnHold = true;
    // The stroke became a right click: its motion and release are swallowed.
    bool m_held = false;
    QPointF m_pressPos;
    QTimer m_holdTimer;
    // A press on the bottom zone that may become a tap.
    bool m_bottomTap = false;
    QPointF m_bottomPos;
    QElapsedTimer m_bottomTime;
    std::function<void()> m_bottomTapHandler;
};

} // namespace KWin
