// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <input_event_spy.h>

namespace KWin
{

// Plasma Fusion (TABLET2 P0 K1): a key press on a hardware keyboard hides the on-screen keyboard,
// as GNOME and iPadOS do. KWin 6.7.5 shows it after a touch or pen tap and keeps it while a
// Bluetooth keyboard types. The on-screen keyboard's own keys reach the seat directly and never
// pass the input spies; buttons that are not alphanumeric keyboards (power, volume, the
// ThinkPad's extra buttons) are skipped.
class FusionKeyboardSpy : public InputEventSpy
{
public:
    FusionKeyboardSpy();
    ~FusionKeyboardSpy() override;

    void keyboardKey(KeyboardKeyEvent *event) override;
};

} // namespace KWin
