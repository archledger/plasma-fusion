// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

#include "keyboardspy.h"

#include <QVariant>
#include <core/inputdevice.h>
#include <input.h>
#include <input_event.h>
#include <inputmethod.h>
#include <main.h>

namespace KWin
{

FusionKeyboardSpy::FusionKeyboardSpy()
{
    input()->installInputEventSpy(this);
}

FusionKeyboardSpy::~FusionKeyboardSpy()
{
    if (input()) {
        input()->uninstallInputEventSpy(this);
    }
}

void FusionKeyboardSpy::keyboardKey(KeyboardKeyEvent *event)
{
    if (event->state != KeyboardKeyState::Pressed || !event->device) {
        return;
    }
    // libinput devices tell; others (emulated input, remote keyboards) count as keyboards.
    const QVariant alphaNumeric = event->device->property("alphaNumericKeyboard");
    if (alphaNumeric.isValid() && !alphaNumeric.toBool()) {
        return;
    }
    InputMethod *inputMethod = kwinApp()->inputMethod();
    if (!inputMethod || !inputMethod->isVisible()) {
        return;
    }
    qInfo("plasmafusion-navigation: hardware key on %s: on-screen keyboard hidden", qPrintable(event->device->name()));
    inputMethod->hide();
}

} // namespace KWin
