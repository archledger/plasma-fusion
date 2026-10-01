// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

#include "penfilter.h"

#include <core/output.h>
#include <input_event.h>
#include <pointer_input.h>
#include <touch_input.h>

#include <QLineF>
#include <linux/input-event-codes.h>
#include <window.h>
#include <workspace.h>

using namespace std::chrono_literals;

namespace KWin
{

// A touch point id no touchscreen hands out (libinput slots are small numbers).
static constexpr qint32 s_penTouchId = 0x7f50;
// The pen stays a pen this close to the bottom edge: the navigation gestures' zone (20 px) and a margin.
static constexpr qreal s_bottomZone = 24;
// Press and hold: the time and the travel allowed (research: long press 500-600 ms, 10 px).
static constexpr auto s_holdTime = 500ms;
static constexpr qreal s_holdSlop = 10;

static std::chrono::microseconds now()
{
    return std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now().time_since_epoch());
}

FusionPenFilter::FusionPenFilter()
    : InputEventFilter(InputFilterOrder::ScreenEdge)
    , m_drawingApps(defaultDrawingApps())
{
    input()->installInputEventFilter(this);
    m_holdTimer.setSingleShot(true);
    m_holdTimer.setInterval(s_holdTime);
    QObject::connect(&m_holdTimer, &QTimer::timeout, [this]() {
        holdTimeout();
    });
}

FusionPenFilter::~FusionPenFilter()
{
    if (input()) {
        if (m_converting) {
            finish(now(), nullptr);
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
        finish(now(), nullptr);
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

void FusionPenFilter::setRightClickOnHold(bool enabled)
{
    m_rightClickOnHold = enabled;
    if (!enabled) {
        m_holdTimer.stop();
    }
}

void FusionPenFilter::setBottomTapHandler(std::function<void()> handler)
{
    m_bottomTapHandler = std::move(handler);
}

bool FusionPenFilter::inBottomZone(const QPointF &pos) const
{
    if (LogicalOutput *output = workspace()->outputAt(pos)) {
        const RectF geometry = output->geometryF();
        return pos.y() >= geometry.y() + geometry.height() - s_bottomZone;
    }
    return false;
}

bool FusionPenFilter::exempt(const QPointF &pos) const
{
    if (inBottomZone(pos)) {
        return true;
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

// The Plasma shell's surfaces (home screen, dock, launcher, top bar, widgets) open their menus on a
// touch long press, as with a finger. Over them the pen stays a finger for the whole hold: the right
// click that stands in for a long press in other apps arrived after the touch was cancelled and
// opened nothing there (PLASMA-68: a pen hold on a home-screen tile showed no menu, a finger hold did).
bool FusionPenFilter::shellLongPress(const QPointF &pos) const
{
    if (Window *window = input()->findToplevel(pos)) {
        return window->resourceClass().compare(QLatin1String("plasmashell"), Qt::CaseInsensitive) == 0
            || window->desktopFileName() == QLatin1String("org.kde.plasmashell");
    }
    return false;
}

void FusionPenFilter::finish(std::chrono::microseconds time, InputDevice *device)
{
    m_holdTimer.stop();
    m_converting = false;
    if (m_held) {
        // The touch was cancelled when the hold was recognised; the right click comes on lift, as
        // with Windows Ink.
        m_held = false;
        qInfo("plasmafusion-navigation: pen press and hold: right click at %.0f,%.0f", m_pressPos.x(), m_pressPos.y());
        // Each step ends with a frame (clients act on wl_pointer.frame). The release follows 80 ms
        // later: Qt opens a context menu on the press and grabs the pop-up with that press, and a
        // release sent with it made KWin dismiss the menu at once (session ph1; a real click holds
        // the button about as long).
        input()->pointer()->processMotionAbsolute(m_pressPos, time);
        input()->pointer()->processFrame();
        input()->pointer()->processButton(BTN_RIGHT, PointerButtonState::Pressed, time);
        input()->pointer()->processFrame();
        QTimer::singleShot(80ms, []() {
            if (input()) {
                input()->pointer()->processButton(BTN_RIGHT, PointerButtonState::Released, now());
                input()->pointer()->processFrame();
            }
        });
        return;
    }
    input()->touch()->processUp(s_penTouchId, time, device);
    input()->touch()->frame();
}

void FusionPenFilter::holdTimeout()
{
    if (!m_converting || m_held) {
        return;
    }
    m_held = true;
    // the app sees the touch cancelled: no tap, no drag; the right click follows on lift
    input()->touch()->cancel();
}

bool FusionPenFilter::tabletToolTipEvent(TabletToolTipEvent *event)
{
    if (event->type == TabletToolTipEvent::Press) {
        m_bottomTap = m_active && !m_converting && inBottomZone(event->position);
        if (m_bottomTap) {
            m_bottomPos = event->position;
            m_bottomTime.start();
        }
        if (!m_active || m_converting || exempt(event->position)) {
            return false;
        }
        m_converting = true;
        m_held = false;
        m_pressPos = event->position;
        input()->touch()->processDown(s_penTouchId, event->position, event->timestamp, event->device);
        input()->touch()->frame();
        if (m_rightClickOnHold && !shellLongPress(event->position)) {
            m_holdTimer.start();
        }
        return true;
    }
    if (!m_converting) {
        // A quick tap on the bottom zone shows the dock; the event still goes where it went.
        if (m_bottomTap) {
            m_bottomTap = false;
            if (m_bottomTime.elapsed() < 400 && QLineF(m_bottomPos, event->position).length() <= s_holdSlop && m_bottomTapHandler) {
                qInfo("plasmafusion-navigation: pen tap on the home handle: dock");
                m_bottomTapHandler();
            }
        }
        return false;
    }
    finish(event->timestamp, event->device);
    return true;
}

bool FusionPenFilter::tabletToolAxisEvent(TabletToolAxisEvent *event)
{
    if (!m_converting) {
        if (m_bottomTap && QLineF(m_bottomPos, event->position).length() > s_holdSlop) {
            m_bottomTap = false; // a stroke, not a tap
        }
        return false;
    }
    if (m_held) {
        return true;
    }
    if (m_holdTimer.isActive() && QLineF(m_pressPos, event->position).length() > s_holdSlop) {
        m_holdTimer.stop();
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
