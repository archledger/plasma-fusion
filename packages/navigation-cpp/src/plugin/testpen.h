// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <QObject>
#include <QPointF>
#include <memory>

namespace KWin
{

class FusionTestPenDevice;
class FusionTestPenTool;

// Test tooling, never in a normal session: with PLASMA_FUSION_TEST_PEN=1 in KWin's environment
// (private test sessions only) the plugin adds a virtual pen to KWin and drives it from D-Bus
// (service org.kde.KWin, path /org/plasmafusion/TestPen), so pen behaviour can be tested where no
// real pen exists. Its events take the same path through KWin as a libinput pen's.
class FusionTestPen : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.plasmafusion.TestPen")

public:
    explicit FusionTestPen(QObject *parent = nullptr);
    ~FusionTestPen() override;

public Q_SLOTS:
    Q_SCRIPTABLE void proximity(double x, double y, bool in);
    Q_SCRIPTABLE void tip(double x, double y, bool down);
    Q_SCRIPTABLE void move(double x, double y);

private:
    std::unique_ptr<FusionTestPenDevice> m_device;
    std::unique_ptr<FusionTestPenTool> m_tool;
    bool m_tipDown = false;
};

} // namespace KWin
