/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <input.h>

#include <QList>
#include <QPointer>

namespace KWin
{
class Window;

// Plasma Fusion: hides a dock again that the navigation effect revealed over an app (a short swipe
// up, a pen tap on the home handle). Plasma shows a dodging or auto-hiding panel again when the
// pointer leaves it; a dock revealed by touch is never entered by the pointer, so it stayed over
// the app. Now the next touch or click outside the dock, or an app activated from it, hides it
// again the way Plasma's own request does (hidden, its screen edge reserved), but only while an app
// window still overlaps it, so on the home screen the dock stays.
class FusionDockRehide : public InputEventFilter
{
public:
    FusionDockRehide();
    ~FusionDockRehide() override;

    // Docks just revealed with showOnScreenEdge().
    void revealed(const QList<Window *> &docks);

    bool touchDown(TouchDownEvent *event) override;
    bool pointerButton(PointerButtonEvent *event) override;

private:
    void pressAt(const QPointF &pos);
    void rehide();
    static bool overlapped(Window *dock);

    QList<QPointer<Window>> m_docks;
    QMetaObject::Connection m_activation;
};

} // namespace KWin
