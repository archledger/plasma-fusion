/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

// Test holder: exposes the banner triage rules to triagetest.cpp, importing the rules file the way
// the applet does. Functions of the rules that return an object are read twice, once per field.
import QtQuick

import "../src/global/BannerTriage.js" as Triage

Item {
    readonly property string idle: Triage.STATE_IDLE
    readonly property string requested: Triage.STATE_REQUESTED
    readonly property string active: Triage.STATE_ACTIVE

    function newestBannerIndex(banners) {
        return Triage.newestBannerIndex(banners);
    }
    function transitionState(state, event) {
        return Triage.transition(state, event).state;
    }
    function transitionRestores(state, event) {
        return Triage.transition(state, event).restoreFocus;
    }
    function escapeAction(interactionActive, replying, spent, autoRepeat) {
        return Triage.escapeAction(interactionActive, replying, spent, autoRepeat);
    }
    function enterAction(interactionActive, focusOnContent, hasDefaultAction, spent, autoRepeat) {
        return Triage.enterAction(interactionActive, focusOnContent, hasDefaultAction, spent, autoRepeat);
    }
}
