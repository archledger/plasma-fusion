# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Konsole profile of the Plasma Fusion desktop: the dark terminal of the boards (also under
# Plasma Fusion Light, as on the Light boards), Fedora's monospace font at 11 pt, a block
# cursor and a 14 px margin like the board terminal. Make it the default with
#   kwriteconfig6 --file konsolerc --group "Desktop Entry" --key DefaultProfile "Plasma Fusion.profile"

[General]
Name=Plasma Fusion
Parent=FALLBACK/
Icon=utilities-terminal
TerminalMargin=14
TerminalCenter=false

[Appearance]
ColorScheme=PlasmaFusionDark
Font=Noto Sans Mono,11,-1,5,400,0,0,0,0,0,0,0,0,0,0,1,,0,0
LineSpacing=2
BoldIntense=true
AntiAliasFonts=true

[Cursor Options]
CursorShape=0

[Terminal Features]
BlinkingCursorEnabled=false
