/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/
#pragma once

#include <QString>

namespace PlasmaFusion
{

// ~/.config/plasmafusionrc [Decoration] ButtonStyle (contract with the Plasma Fusion settings module)
enum class ButtonStyle {
    RightGlyphs, // default: 28 px circles with glyphs on the right
    LeftCircles, // 13 px circles on the left, title centred
    ShowOnHover, // like RightGlyphs, buttons hidden until the pointer is over the title bar
};

struct FusionConfig {
    ButtonStyle buttonStyle = ButtonStyle::RightGlyphs;
    // [Decoration] SnapLayoutsOnHover (default false, owner decision 4 "hold"): true adds the
    // hover trigger (resting 600 ms on maximize opens the snap layouts) to the hold trigger.
    bool snapLayoutsOnHover = false;
    // kwinrc [Plugins] plasmafusion-snapEnabled: without the script there is no flyout, so the
    // maximize button keeps its plain behaviour.
    bool snapScriptEnabled = false;
    // kdeglobals [KDE] AnimationDurationFactor (0 disables animations)
    qreal animationFactor = 1.0;

    // Holding maximize for 600 ms opens the snap layouts whenever the script is enabled.
    bool snapHold() const
    {
        return snapScriptEnabled;
    }
    // Resting on maximize for 600 ms opens them too, only with SnapLayoutsOnHover=true (the
    // decoration also turns this off in tablet mode).
    bool snapHover() const
    {
        return snapLayoutsOnHover && snapScriptEnabled;
    }

    // The current settings. reload() re-reads the files (every decoration calls it on KWin's
    // reconfigure; the files are read once per event-loop pass).
    static const FusionConfig &self();
    static void reload();
    static ButtonStyle parseStyle(const QString &value);
};

} // namespace PlasmaFusion
