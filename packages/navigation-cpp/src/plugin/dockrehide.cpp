/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "dockrehide.h"

#include <core/output.h>
#include <input_event.h>
#include <screenedge.h>
#include <window.h>
#include <workspace.h>

#include <QTimer>

namespace KWin
{

FusionDockRehide::FusionDockRehide()
    : InputEventFilter(InputFilterOrder::ScreenEdge)
{
    input()->installInputEventFilter(this);
}

FusionDockRehide::~FusionDockRehide()
{
    QObject::disconnect(m_activation);
    if (input()) {
        input()->uninstallInputEventFilter(this);
    }
}

void FusionDockRehide::revealed(const QList<Window *> &docks)
{
    for (Window *dock : docks) {
        if (!m_docks.contains(dock)) {
            m_docks.append(dock);
        }
    }
    if (m_docks.isEmpty() || m_activation) {
        return;
    }
    // An app opened or switched to from the dock: hide once it is active (and covers the dock).
    m_activation = QObject::connect(workspace(), &Workspace::windowActivated, workspace(), [this](Window *window) {
        if (window && !window->isDock() && window->isNormalWindow()) {
            QTimer::singleShot(250, workspace(), [this]() {
                rehide();
            });
        }
    });
}

bool FusionDockRehide::touchDown(TouchDownEvent *event)
{
    pressAt(event->pos);
    return false;
}

bool FusionDockRehide::pointerButton(PointerButtonEvent *event)
{
    if (event->state == PointerButtonState::Pressed) {
        pressAt(event->position);
    }
    return false;
}

void FusionDockRehide::pressAt(const QPointF &pos)
{
    if (m_docks.isEmpty()) {
        return;
    }
    for (const QPointer<Window> &dock : std::as_const(m_docks)) {
        if (dock && !dock->isHidden() && dock->frameGeometry().contains(pos)) {
            return; // a press on the dock itself: it stays
        }
    }
    // after this event is delivered: no window changes in the middle of input processing
    QTimer::singleShot(0, workspace(), [this]() {
        rehide();
    });
}

bool FusionDockRehide::overlapped(Window *dock)
{
    const RectF area = dock->frameGeometry();
    const auto windows = workspace()->windows();
    for (Window *window : windows) {
        if (window == dock || !window->isNormalWindow() || window->isMinimized() || window->isHidden()
            || !window->isOnCurrentDesktop() || window->output() != dock->output()) {
            continue;
        }
        if (window->frameGeometry().intersects(area)) {
            return true;
        }
    }
    return false;
}

void FusionDockRehide::rehide()
{
    int hidden = 0;
    for (const QPointer<Window> &dock : std::as_const(m_docks)) {
        if (!dock || dock->isHidden() || !overlapped(dock)) {
            continue;
        }
        dock->setHidden(true);
        workspace()->screenEdges()->reserve(dock, ElectricBottom);
        ++hidden;
    }
    if (hidden > 0 || std::none_of(m_docks.cbegin(), m_docks.cend(), [](const QPointer<Window> &dock) {
            return dock && !dock->isHidden();
        })) {
        qInfo("plasmafusion-navigation: revealed dock hidden again: %d", hidden);
        m_docks.clear();
        QObject::disconnect(m_activation);
        m_activation = {};
    }
}

} // namespace KWin
