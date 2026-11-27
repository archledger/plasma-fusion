# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later

# One case of guardtest.cmake: the directory guard (../cmake/PluginDirGuard.cmake) on the
# directory named in COPY_FILE (the file holds the value as it was written) against QT_DIR, and
# when EXTRA_DIR is given, as another directory Plasma loads plugins from. It ends the script with
# the guard's message when the directory is refused, and exits 0 when the directory is allowed.
cmake_minimum_required(VERSION 3.22)

include("${GUARD_MODULE}")
file(READ "${COPY_FILE}" COPY_DIR)
if(EXTRA_DIR)
  pf_check_plugin_dir("${COPY_DIR}" "${QT_DIR}" _allowed "${EXTRA_DIR}")
else()
  pf_check_plugin_dir("${COPY_DIR}" "${QT_DIR}" _allowed)
endif()
