// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
// Fixture for tools/checks/a11y-lint.py: a package control named from its text at its uses.
import QtQuick
import QtQuick.Templates as T

T.AbstractButton {
    Accessible.name: text
    Accessible.role: Accessible.Button
}
