// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

#include "penfilter.h"

#include <core/output.h>
#include <input_event.h>
#include <touch_input.h>
#include <window.h>
#include <workspace.h>

using namespace std::chrono_literals;

namespace KWin
{

// A touch point id no touchscreen hands out (libinput slots are small numbers).
static constexpr qint32 s_penTouchId = 0x7f50;
// The pen stays a pen this close to the bottom edge: the navigation gestures' zone (20 px) and a margin.
static constexpr qreal s_bottomZone = 24;

FusionPenFilter::FusionPenFilter()
    : InputEventFilter(InputFilterOrder::ScreenEdge)
    , m_drawingApps(defaultDrawingApps())
{
    input()->installInputEventFilter(this);
}

FusionPenFilter::~FusionPenFilter()
{
    if (input()) {
        if (m_converting) {
            finish(std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now().time_since_epoch()), nullptr);
        }
        input()->uninstallInputEventFilter(this);
    }
}

QStringList FusionPenFilter::defaultDrawingApps()
{
    return {
        QStringLiteral("com.github.xournalpp.xournalpp"),
        QStringLiteral("xournalpp"),
        QStringLiteral("com.github.flxzt.rnote"),
        QStringLiteral("rnote"),
        QStringLiteral("org.kde.krita"),
        QStringLiteral("krita"),
        QStringLiteral("org.inkscape.inkscape"),
        QStringLiteral("inkscape"),
        QStringLiteral("org.gimp.gimp"),
        QStringLiteral("gimp"),
        QStringLiteral("org.mypaint.mypaint"),
        QStringLiteral("mypaint"),
        QStringLiteral("org.kde.kolourpaint"),
    };
}

void FusionPenFilter::setActive(bool active)
{
    if (!active && m_converting) {
        finish(std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now().time_since_epoch()), nullptr);
    }
    m_active = active;
}

bool FusionPenFilter::isActive() const
{
    return m_active;
}

void FusionPenFilter::setDrawingApps(const QStringList &apps)
{
    m_drawingApps.clear();
    for (const QString &app : apps) {
        const QString name = app.trimmed().toLower();
        if (!name.isEmpty()) {
            m_drawingApps.append(name);
        }
    }
}

bool FusionPenFilter::exempt(const QPointF &pos) const
{
    if (LogicalOutput *output = workspace()->outputAt(pos)) {
        const RectF geometry = output->geometryF();
        if (pos.y() >= geometry.y() + geometry.height() - s_bottomZone) {
            return true;
        }
    }
    if (Window *window = input()->findToplevel(pos)) {
        const QString windowClass = window->resourceClass().toLower();
        const QString desktopFile = window->desktopFileName().toLower();
        for (const QString &app : m_drawingApps) {
            if (windowClass == app || desktopFile == app) {
                return true;
            }
        }
    }
    return false;
}

void FusionPenFilter::finish(std::chrono::microseconds time, InputDevice *device)
{
    m_converting = false;
    input()->touch()->processUp(s_penTouchId, time, device);
    input()->touch()->frame();
}

bool FusionPenFilter::tabletToolTipEvent(TabletToolTipEvent *event)
{
    if (event->type == TabletToolTipEvent::Press) {
        if (!m_active || m_converting || exempt(event->position)) {
            return false;
        }
        m_converting = true;
        input()->touch()->processDown(s_penTouchId, event->position, event->timestamp, event->device);
        input()->touch()->frame();
        return true;
    }
    if (!m_converting) {
        return false;
    }
    finish(event->timestamp, event->device);
    return true;
}

bool FusionPenFilter::tabletToolAxisEvent(TabletToolAxisEvent *event)
{
    if (!m_converting) {
        return false;
    }
    input()->touch()->processMotion(s_penTouchId, event->position, event->timestamp, event->device);
    input()->touch()->frame();
    return true;
}

bool FusionPenFilter::tabletToolProximityEvent(TabletToolProximityEvent *event)
{
    if (m_converting && event->type == TabletToolProximityEvent::LeaveProximity) {
        finish(event->timestamp, event->device);
    }
    return false;
}

} // namespace KWin
