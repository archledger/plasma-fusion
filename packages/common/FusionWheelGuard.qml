// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick

// Scroll safety (survey U8, KDE Discuss #uxquirk thread): a wheel that is still turning from a page
// scroll when the pointer passes over a wheel control must not change its value. Declared in the
// item that takes the wheel (beside its WheelHandler), it follows the pointer over that item; the
// WheelHandler asks accept() before acting on a wheel event:
//
//   FusionWheelGuard { id: wheelGuard }
//   WheelHandler { onWheel: event => { if (!wheelGuard.accept(Date.now())) return; ... } }
//
// The rule is Firefox's wheel transaction (a scroll stays with the element it started on) seen from
// the control the pointer moved to:
// - a wheel event less than `settle` ms after the pointer entered the item, or with no hover seen
//   yet, belongs to a scroll that began elsewhere: it and the rest of that scroll are ignored;
// - that scroll ends after `transactionTimeout` ms without a wheel event, or at the first wheel
//   event more than `moveDelay` ms after the pointer moved again (moves within `moveDelay` of a
//   wheel event are part of the scroll, as in Firefox);
// - a wheel that starts after the pointer has been over the item for `settle` ms acts at once, and
//   so does the rest of that scroll, so turning the wheel on purpose works as before.
// Timings: Firefox's mousewheel.transaction.timeout (1500 ms) and ignoremovedelay (100 ms); settle
// is about one simple reaction time (240 ms in Card, Moran and Newell's Model Human Processor), the
// least a person needs to start turning the wheel after the pointer arrives. Tests:
// packages/common/tests/wheel_guard_test.py.
HoverHandler {
    id: guard

    readonly property int settle: 250
    readonly property int transactionTimeout: 1500
    readonly property int moveDelay: 100

    // Times in ms (Date.now()), -1 when unset.
    property real enteredAt: -1
    property real lastWheelAt: -1
    property real movedAt: -1
    // A scroll that began elsewhere is passing over the item.
    property bool passing: false

    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

    onHoveredChanged: hovered ? pointerEntered(Date.now()) : pointerLeft()
    onPointChanged: if (hovered) pointerMoved(Date.now())

    function pointerEntered(now: real): void {
        enteredAt = now;
        lastWheelAt = -1;
        movedAt = -1;
        passing = false;
    }
    function pointerLeft(): void {
        enteredAt = -1;
        lastWheelAt = -1;
        movedAt = -1;
        passing = false;
    }
    function pointerMoved(now: real): void {
        if (passing && movedAt < 0 && lastWheelAt >= 0 && now - lastWheelAt > moveDelay) {
            movedAt = now;
        }
    }
    // True when the wheel event at `now` may change the item's value.
    function accept(now: real): bool {
        if (enteredAt < 0) {
            enteredAt = now;
        }
        const scrolling = lastWheelAt >= 0 && now - lastWheelAt <= transactionTimeout;
        if (passing && (!scrolling || (movedAt >= 0 && now - movedAt > moveDelay))) {
            passing = false;
            movedAt = -1;
        } else if (!passing && !scrolling && now - enteredAt < settle) {
            passing = true;
        }
        lastWheelAt = now;
        return !passing;
    }
}
