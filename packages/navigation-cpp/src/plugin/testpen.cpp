// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

#include "testpen.h"

#include <QDBusConnection>
#include <chrono>
#include <core/inputdevice.h>
#include <input.h>

namespace KWin
{

class FusionTestPenTool : public InputDeviceTabletTool
{
public:
    quint64 serialId() const override
    {
        return 1;
    }
    quint64 uniqueId() const override
    {
        return 0x50466e;
    }
    Type type() const override
    {
        return Pen;
    }
    QList<Capability> capabilities() const override
    {
        return {Pressure};
    }
};

class FusionTestPenDevice : public InputDevice
{
public:
    QString name() const override
    {
        return QStringLiteral("Plasma Fusion test pen");
    }
    bool isEnabled() const override
    {
        return true;
    }
    void setEnabled(bool) override
    {
    }
    bool isKeyboard() const override
    {
        return false;
    }
    bool isPointer() const override
    {
        return false;
    }
    bool isTouchpad() const override
    {
        return false;
    }
    // Also a touch device, so the seat offers touch to clients in a session without a touchscreen
    // (the ThinkPad has one); the pen filter's finger events need it.
    bool isTouch() const override
    {
        return true;
    }
    bool isTabletTool() const override
    {
        return true;
    }
    bool isTabletPad() const override
    {
        return false;
    }
    bool isTabletModeSwitch() const override
    {
        return false;
    }
    bool isLidSwitch() const override
    {
        return false;
    }
};

static std::chrono::microseconds now()
{
    return std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now().time_since_epoch());
}

FusionTestPen::FusionTestPen(QObject *parent)
    : QObject(parent)
    , m_device(std::make_unique<FusionTestPenDevice>())
    , m_tool(std::make_unique<FusionTestPenTool>())
{
    input()->addInputDevice(m_device.get());
    QDBusConnection::sessionBus().registerObject(QStringLiteral("/org/plasmafusion/TestPen"), this, QDBusConnection::ExportScriptableSlots);
    qWarning("plasmafusion-navigation: TEST PEN active (PLASMA_FUSION_TEST_PEN is set)");
}

FusionTestPen::~FusionTestPen()
{
    QDBusConnection::sessionBus().unregisterObject(QStringLiteral("/org/plasmafusion/TestPen"));
    if (input()) {
        input()->removeInputDevice(m_device.get());
    }
}

void FusionTestPen::proximity(double x, double y, bool in)
{
    Q_EMIT m_device->tabletToolProximityEvent(QPointF(x, y), 0, 0, 0, in ? 0 : 1, in, 0, m_tool.get(), now(), m_device.get());
}

void FusionTestPen::tip(double x, double y, bool down)
{
    m_tipDown = down;
    Q_EMIT m_device->tabletToolTipEvent(QPointF(x, y), down ? 0.5 : 0, 0, 0, 0, 0, down, 0, m_tool.get(), now(), m_device.get());
}

void FusionTestPen::move(double x, double y)
{
    Q_EMIT m_device->tabletToolAxisEvent(QPointF(x, y), m_tipDown ? 0.5 : 0, 0, 0, 0, 0, m_tipDown, 0, m_tool.get(), now(), m_device.get());
}

} // namespace KWin
