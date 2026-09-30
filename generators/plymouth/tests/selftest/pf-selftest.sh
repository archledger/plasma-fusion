#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# Drives plymouth through the theme's other states; each step is announced on ttyS0 for
# tests/vmrun.py, which takes the screenshot and types the answers.
say() { echo "PFSTEP $*" > /dev/ttyS0; }
msg="Checking the file system on /dev/vda2 · 42 % done"
sleep 4
plymouth display-message --text="$msg"
say message
sleep 5
plymouth hide-message --text="$msg"
say question
answer=$(plymouth ask-question --prompt="Name of the recovery host:")
say "answer=$answer"
say recovery
plymouth ask-for-password --prompt="Please enter recovery key for disk Samsung_SSD_870_EVO_1TB (luks-d6f1c0de) on /home:" > /dev/null
say pin
plymouth ask-for-password --prompt="Please enter LUKS2 token PIN:" > /dev/null
say other
plymouth ask-for-password --prompt="Password for the backup server on a very long host name that does not fit the screen at all, example.org:" > /dev/null
plymouth change-mode --updates
plymouth system-update --progress=42
say update
sleep 5
plymouth system-update --progress=87
plymouth display-message --text="Installing 27 of 31 packages"
say update2
sleep 5
plymouth hide-message --text="Installing 27 of 31 packages"
plymouth change-mode --boot-up
say "done"
