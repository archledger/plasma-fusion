# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later

# Unit test of the directory guard of the notification applet copy (../cmake/PluginDirGuard.cmake).
# No compiler and no packages: it makes a small tree of directories and symbolic links and runs the
# guard on each case in a child CMake. A case says whether the guard must refuse the directory,
# and with which words, or allow it; it fails when the guard does otherwise. ctest runs it as
# notifications-plugin-dir-guard.
#
#   cmake -DGUARD_MODULE=<dir>/PluginDirGuard.cmake -P guardtest.cmake
cmake_minimum_required(VERSION 3.22)
if(NOT DEFINED GUARD_MODULE)
  message(FATAL_ERROR "usage: cmake -DGUARD_MODULE=<dir>/PluginDirGuard.cmake -P guardtest.cmake")
endif()

# A stand-in for Qt's plugin directory, and links to it from elsewhere.
set(scratch "${CMAKE_CURRENT_BINARY_DIR}/guard-tree")
file(REMOVE_RECURSE "${scratch}")
file(MAKE_DIRECTORY "${scratch}/qt/plugins/plasma/applets" "${scratch}/elsewhere" "${scratch}/dir")
execute_process(COMMAND ln -s "${scratch}/qt/plugins" "${scratch}/link")
execute_process(COMMAND ln -s "${scratch}/qt" "${scratch}/lib")
execute_process(COMMAND ln -s "${scratch}/qt/plugins/plasma" "${scratch}/dir/plasma")
execute_process(COMMAND ln -s "${scratch}/qt/plugins/not-yet" "${scratch}/dangling")
execute_process(COMMAND ln -s "${scratch}/elsewhere" "${scratch}/alias")

set(qt "${scratch}/qt/plugins")
set(stock "is Qt's plugin directory or inside it")
# directory|Qt's directory|verdict|the words a refusal must have|what the case is
set(cases
  "lib64/qt6/plugins|${qt}|stops|must be an absolute path|a relative directory"
  "${qt}|${qt}|stops|${stock}|Qt's directory itself"
  "${qt}/|${qt}|stops|${stock}|Qt's directory with a trailing slash"
  "${qt}/plasma|${qt}|stops|${stock}|a directory inside Qt's"
  "${qt}/plasma/../applets|${qt}|stops|${stock}|a directory inside Qt's, written with .."
  "${scratch}/qt/plugins/../plugins|${qt}|stops|${stock}|Qt's directory, leaving it with .. and coming back"
  "${scratch}/link|${qt}|stops|${stock}|a symbolic link to Qt's directory"
  "${scratch}/link/sub|${qt}|stops|${stock}|a directory that does not exist yet, under a link to Qt's"
  "${scratch}/link/../plugins|${qt}|stops|${stock}|the parent of a link's target, then down again: a lexical .. would hide it"
  "${scratch}/lib/plugins|${qt}|stops|${stock}|Qt's directory through a link above it"
  "${scratch}/dir|${qt}|stops|${stock}|a directory whose plasma is a link into Qt's"
  "${scratch}/dangling|${qt}|stops|${stock}|a dangling link into Qt's directory"
  "${scratch}/libexec/plasma-fusion/qt6/plugins|${qt}|allows||the default directory, not existing yet"
  "${scratch}/elsewhere|${qt}|allows||another directory"
  "${scratch}/alias|${qt}|allows||a link to another directory"
  "${scratch}/alias/sub|${qt}|allows||a directory that does not exist yet, under a link to another directory"
  "${qt}/../qt6/qt6/plugins|${qt}|allows||a look-alike outside Qt's directory"
  "${qt}/../other|${qt}|allows||a sibling of Qt's directory")

set(passed 0)
set(failed 0)
foreach(case IN LISTS cases)
  string(REPLACE "|" ";" fields "${case}")
  list(GET fields 0 copy)
  list(GET fields 1 its_qt)
  list(GET fields 2 verdict)
  list(GET fields 3 words)
  list(GET fields 4 what)
  set(output "")
  execute_process(COMMAND "${CMAKE_COMMAND}" "-DGUARD_MODULE=${GUARD_MODULE}" "-DCOPY_DIR=${copy}"
                          "-DQT_DIR=${its_qt}" -P "${CMAKE_CURRENT_LIST_DIR}/guardcase.cmake"
                  RESULT_VARIABLE result OUTPUT_VARIABLE output ERROR_VARIABLE output)
  # CMake wraps a long message over lines; the words of a refusal are compared as one line.
  string(REGEX REPLACE "[ \t\r\n]+" " " flat "${output}")
  set(ok FALSE)
  if(verdict STREQUAL "stops")
    if(NOT result EQUAL 0 AND flat MATCHES "${words}")
      set(ok TRUE)
    endif()
  elseif(result EQUAL 0 AND output STREQUAL "")
    set(ok TRUE)
  endif()
  if(ok)
    math(EXPR passed "${passed} + 1")
    message(STATUS "PASS ${verdict}: ${what}")
  else()
    math(EXPR failed "${failed} + 1")
    message(STATUS "FAIL ${verdict}: ${what} (exit ${result}) ${output}")
  endif()
endforeach()
file(REMOVE_RECURSE "${scratch}")

math(EXPR total "${passed} + ${failed}")
message(STATUS "plugin directory guard: ${passed} of ${total} cases")
if(NOT failed EQUAL 0)
  message(FATAL_ERROR "${failed} case(s) of the plugin directory guard failed")
endif()
