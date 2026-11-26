# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later

# One case of guardtest.cmake: the directory guard (../cmake/PluginDirGuard.cmake) on COPY_DIR
# against QT_DIR. It ends the script with the guard's message when the directory is refused, and
# exits 0 when the directory is allowed.
cmake_minimum_required(VERSION 3.22)

include("${GUARD_MODULE}")
pf_check_plugin_dir("${COPY_DIR}" "${QT_DIR}")
