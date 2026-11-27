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
    function transitionState(state, event, replyStarted) {
        return Triage.transition(state, event, replyStarted).state;
    }
    function transitionRestores(state, event, replyStarted) {
        return Triage.transition(state, event, replyStarted).restoreFocus;
    }
    function recordedWindow(takenBannerActive, activeTask, earlierRecord) {
        return Triage.recordedWindow(takenBannerActive, activeTask, earlierRecord);
    }
    function identity(id, updated, summary, body) {
        return Triage.identity(id, updated, summary, body);
    }
    function taskCoordinates(task) {
        return Triage.taskCoordinates(task);
    }
    function eligible(visible, jobPopup, replyStarted) {
        return Triage.eligible(visible, jobPopup, replyStarted);
    }
    function escapeAction(interactionActive, replyFieldFocused, dismissed, autoRepeat) {
        return Triage.escapeAction(interactionActive, replyFieldFocused, dismissed, autoRepeat);
    }
    function enterAction(interactionActive, focusOnContent, hasDefaultAction, autoRepeat) {
        return Triage.enterAction(interactionActive, focusOnContent, hasDefaultAction, autoRepeat);
    }
    function inReplyField(item, content) {
        return Triage.inReplyField(item, content);
    }

    // A small tree of real items for the walk of inReplyField: the banner's content, in it the
    // reply field (marked) with its editor, and next to it a button.
    Item {
        id: walkContent
        Item {
            id: walkField
            readonly property bool isReplyField: true
            Item { id: walkEditor }
        }
        Item { id: walkButton }
    }
    readonly property Item walkContentItem: walkContent
    readonly property Item walkFieldItem: walkField
    readonly property Item walkEditorItem: walkEditor
    readonly property Item walkButtonItem: walkButton
}
