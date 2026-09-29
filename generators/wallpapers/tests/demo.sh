#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# Test only: prints the board's terminal lines and the ANSI palette, then a shell with a teal prompt.
mkdir -p ~/fusion && cd ~/fusion
printf '\e[36m~/fusion $\e[0m make theme\n'
printf '\e[2m[ 64%%] Building icons (216 of 340)\e[0m\n'
printf '\e[2m[ 71%%] Packing cursors\e[0m\n'
printf '\e[1;33mwarning:\e[22m 2 icons have no 16 px version\e[0m\n'
printf '\e[36m~/fusion $\e[0m ls --color\n'
printf '\e[1;34mcursors\e[0m  \e[1;34micons\e[0m  \e[32mbuild.sh\e[0m  Makefile  \e[35mpreview.png\e[0m  \e[31mold.tar.gz\e[0m\n'
printf '\e[36m~/fusion $\e[0m colours\n'
for i in 0 1 2 3 4 5 6 7; do printf '\e[3%dm %d normal \e[0m' $i $i; done; printf '\n'
for i in 0 1 2 3 4 5 6 7; do printf '\e[9%dm %d bright \e[0m' $i $i; done; printf '\n'
for i in 0 1 2 3 4 5 6 7; do printf '\e[2;3%dm %d faint  \e[0m' $i $i; done; printf '\n'
export PS1='\[\e[36m\]\w $\[\e[0m\] '
exec bash --norc -i
