// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
// Offscreen test stand-in for KWin's Options singleton (test use only): the harness emits
// configChanged() as KWin does when it reloads its configuration.
pragma Singleton
import QtQuick

QtObject {
    signal configChanged()
}
