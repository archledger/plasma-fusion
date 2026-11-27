# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later

# Unit test of the directory guard of the notification applet copy (../cmake/PluginDirGuard.cmake).
# No compiler and no packages.
#
# The first part makes a small tree of directories and symbolic links and runs the guard on each
# case in a child CMake (guardcase.cmake). A case says whether the guard must refuse the directory
# and with which words, or allow it; it fails when the guard does otherwise.
#
# The second part configures a small project (LANGUAGES NONE) that holds the wrapper's own lines,
# from the copy's directory to the one the install uses (CMakeLists.txt), verbatim, around an
# install rule like plasma_add_applet's. The directory is typed in the ways a cache variable can
# be, because install() reads a destination with meanings of its own: a generator expression,
# backslashes and a leading ~. The destination is read from the generated install script: the
# string the guard checked must be the string install() uses, and an allowed copy must leave the
# stand-ins for the stock plugin untouched.
#
# ctest runs it as notifications-plugin-dir-guard.
#
#   cmake -DGUARD_MODULE=<dir>/PluginDirGuard.cmake [-DWRAPPER=<dir>/CMakeLists.txt] -P guardtest.cmake
#
# The tree is made under SCRATCH_DIR (the temporary directory by default), in a directory with a
# name of its own that is removed at the end; nothing else is removed.
cmake_minimum_required(VERSION 3.22)
if(NOT DEFINED GUARD_MODULE)
  message(FATAL_ERROR "usage: cmake -DGUARD_MODULE=<dir>/PluginDirGuard.cmake -P guardtest.cmake")
endif()
if(NOT DEFINED WRAPPER)
  get_filename_component(_guard_dir "${GUARD_MODULE}" DIRECTORY)
  set(WRAPPER "${_guard_dir}/../CMakeLists.txt")
endif()
if(NOT SCRATCH_DIR)
  set(SCRATCH_DIR "$ENV{TMPDIR}")
  if(NOT SCRATCH_DIR)
    set(SCRATCH_DIR "/tmp")
  endif()
endif()
string(RANDOM LENGTH 12 ALPHABET 0123456789abcdef _run)
set(scratch "${SCRATCH_DIR}/pf-notifications-guard-${_run}")
file(MAKE_DIRECTORY "${scratch}")

# Placeholders for characters a CMake list cannot hold in this table: a list separator, list
# brackets, a backslash, a leading tilde.
function(untokenize in out)
  set(text "${in}")
  string(REPLACE "<semi>" ";" text "${text}")
  string(REPLACE "<lb>" "[" text "${text}")
  string(REPLACE "<rb>" "]" text "${text}")
  string(REPLACE "<bs>" "\\" text "${text}")
  string(REPLACE "<tilde>" "~" text "${text}")
  set(${out} "${text}" PARENT_SCOPE)
endfunction()

# ---- The tree ----
set(stock_file "plasma/applets/org.kde.plasma.notifications.so")
# Qt's plugin directory, and links to it from elsewhere.
file(MAKE_DIRECTORY "${scratch}/qt/plugins/plasma/applets" "${scratch}/elsewhere" "${scratch}/dir")
file(WRITE "${scratch}/qt/plugins/${stock_file}" "stock\n")
execute_process(COMMAND ln -s "${scratch}/qt/plugins" "${scratch}/link")
execute_process(COMMAND ln -s "${scratch}/qt" "${scratch}/lib")
execute_process(COMMAND ln -s "${scratch}/qt/plugins/plasma" "${scratch}/dir/plasma")
execute_process(COMMAND ln -s "${scratch}/qt/plugins/not-yet" "${scratch}/dangling")
execute_process(COMMAND ln -s "${scratch}/elsewhere" "${scratch}/alias")
execute_process(COMMAND touch "${scratch}/qt/plugins/plasma/applets/org.kde.plasma.other.so")
# A file-level link to the stock plugin's file.
file(MAKE_DIRECTORY "${scratch}/filelink/plasma/applets")
execute_process(COMMAND ln -s "${scratch}/qt/plugins/${stock_file}" "${scratch}/filelink/${stock_file}")
# A link to a link to another directory.
execute_process(COMMAND ln -s "chain2" "${scratch}/chain1")
execute_process(COMMAND ln -s "elsewhere" "${scratch}/chain2")
# A second stand-in for Qt's plugin directory, whose plasma/applets is itself a link to a
# directory outside it (as a distribution may arrange).
file(MAKE_DIRECTORY "${scratch}/qt2/plugins/plasma" "${scratch}/outside" "${scratch}/same-applets/plasma"
  "${scratch}/other-applets/plasma/applets")
execute_process(COMMAND ln -s "${scratch}/outside" "${scratch}/qt2/plugins/plasma/applets")
execute_process(COMMAND ln -s "${scratch}/outside" "${scratch}/same-applets/plasma/applets")
# A third, in the shape of a system with a merged /usr: lib64 is a relative link to usr/lib64.
# Around it, links whose targets are relative, a link to a link, a target holding "..", a loop,
# and a target with a list bracket in it.
file(MAKE_DIRECTORY "${scratch}/usr/lib64/qt6/plugins/plasma/applets" "${scratch}/usr/lib64/libexec/pf")
file(WRITE "${scratch}/usr/lib64/qt6/plugins/${stock_file}" "stock\n")
execute_process(COMMAND ln -s "usr/lib64" "${scratch}/lib64")
execute_process(COMMAND ln -s "hop2" "${scratch}/hop1")
execute_process(COMMAND ln -s "usr/lib64/qt6/plugins" "${scratch}/hop2")
execute_process(COMMAND ln -s "usr/lib64/../lib64/qt6/plugins" "${scratch}/up")
execute_process(COMMAND ln -s "loopb" "${scratch}/loopa")
execute_process(COMMAND ln -s "loopa" "${scratch}/loopb")
execute_process(COMMAND ln -s "br[/qt/plugins" "${scratch}/target-bracket")
# ... and links to it whose own names hold such characters.
execute_process(COMMAND "ln" "-s" "qt/plugins" "${scratch}/semi;colon")
execute_process(COMMAND ln -s "qt/plugins" "${scratch}/br[a")

set(qt "${scratch}/qt/plugins")
set(qt3 "${scratch}/usr/lib64/qt6/plugins")
set(stock "is Qt's plugin directory or inside it")
set(chars "a character that CMake reads")
set(passed 0)
set(failed 0)

# ---- The guard on each case ----
# directory|Qt's directory|verdict|the words a refusal must have|what the case is|[another directory
# Plasma loads plugins from]
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
  "${scratch}/filelink|${qt}|stops|is a symbolic link|a directory whose plugin file is a link to another file"
  "${scratch}/same-applets|${scratch}/qt2/plugins|stops|is the stock plugin's own|Qt's applets directory is a link outside it, and the copy's applets is the same"
  "${scratch}/libexec/plasma-fusion/qt6/plugins|${qt}|allows||the default directory, not existing yet"
  "${scratch}/elsewhere|${qt}|allows||another directory"
  "${scratch}/alias|${qt}|allows||a link to another directory"
  "${scratch}/alias/sub|${qt}|allows||a directory that does not exist yet, under a link to another directory"
  "${qt}/../qt6/qt6/plugins|${qt}|allows||a look-alike outside Qt's directory"
  "${qt}/../other|${qt}|allows||a sibling of Qt's directory"
  "${scratch}/other-applets|${scratch}/qt2/plugins|allows||next to where Qt's applets link leads, but another directory"
  "${scratch}/lib64/qt6/plugins|${qt3}|stops|${stock}|Qt's directory through a relative link of a system with a merged /usr (lib64 -> usr/lib64)"
  "${scratch}/lib64/qt6/plugins/sub|${qt3}|stops|${stock}|a directory that does not exist yet, under a relative link to a merged /usr"
  "${qt3}|${scratch}/lib64/qt6/plugins|stops|${stock}|the copy in Qt's directory, with Qt's given through a link above it"
  "${scratch}/hop1|${qt3}|stops|${stock}|a link to a link to Qt's directory"
  "${scratch}/hop1/sub|${qt3}|stops|${stock}|a directory that does not exist yet, under a link to a link to Qt's"
  "${scratch}/up|${qt3}|stops|${stock}|a link whose target holds .."
  "${scratch}/up/sub|${qt3}|stops|${stock}|a directory that does not exist yet, under a link whose target holds .."
  "${scratch}/loopa|${qt}|stops|more than 40 symbolic links|a loop of links"
  "${scratch}/target-bracket|${qt}|stops|${chars}|a link whose target holds a list bracket"
  "${scratch}/chain1|${qt}|allows||a link to a link to another directory"
  "${scratch}/usr/lib64/libexec/pf/plugins|${qt3}|allows||another directory under a merged /usr"
  "${qt}<bs>plasma|${qt}|stops|${chars}|a backslash, which install() reads as a separator"
  "${scratch}/$<1:qt/plugins>|${qt}|stops|${chars}|a generator expression, which install() evaluates"
  "${scratch}/semi<semi>colon|${qt}|stops|${chars}|a link to Qt's directory whose name holds a list separator"
  "${qt}/br<lb>a<rb>|${qt}|stops|${chars}|list brackets in a name"
  "${scratch}/br<lb>a/plugins|${qt}|stops|${chars}|a path through a link to Qt's directory whose name holds a list bracket"
  "<tilde>/qtplugins|${qt}|stops|a leading ~|a leading ~, which install() expands to the home directory"
  "${scratch}/qt2/plugins|${qt}|stops|another directory Plasma loads plugins|a directory given as another one Plasma loads plugins from|${scratch}/qt2/plugins"
  "${scratch}/other-applets|${qt}|allows||a directory beside an unrelated one given as another plugin directory|${scratch}/qt2/plugins")

set(number 0)
foreach(case IN LISTS cases)
  math(EXPR number "${number} + 1")
  string(REPLACE "|" ";" fields "${case}")
  list(GET fields 0 copy)
  list(GET fields 1 its_qt)
  list(GET fields 2 verdict)
  list(GET fields 3 words)
  list(GET fields 4 what)
  set(extra "")
  list(LENGTH fields _n)
  if(_n GREATER 5)
    list(GET fields 5 extra)
  endif()
  untokenize("${copy}" copy)
  untokenize("${its_qt}" its_qt)
  # The value travels in a file: on a command line a backslash or a list separator would not
  # arrive as it was written.
  set(value_file "${scratch}/case-${number}")
  file(WRITE "${value_file}" "${copy}")
  set(output "")
  execute_process(COMMAND "${CMAKE_COMMAND}" "-DGUARD_MODULE=${GUARD_MODULE}" "-DCOPY_FILE=${value_file}"
                          "-DQT_DIR=${its_qt}" "-DEXTRA_DIR=${extra}" -P "${CMAKE_CURRENT_LIST_DIR}/guardcase.cmake"
                  RESULT_VARIABLE result OUTPUT_VARIABLE output ERROR_VARIABLE output TIMEOUT 30)
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
    message(STATUS "FAIL ${verdict}: ${what} (exit ${result}) ${flat}")
  endif()
endforeach()

# ---- The guard behind the wrapper's own lines ----
file(STRINGS "${WRAPPER}" wrapper_lines)
set(block "")
set(in_block FALSE)
foreach(line IN LISTS wrapper_lines)
  if(line MATCHES "^set\\(PF_QT_PLUGIN_DIR ")
    set(in_block TRUE)
  endif()
  if(in_block)
    string(APPEND block "${line}\n")
  endif()
  if(in_block AND line MATCHES "^set\\(KDE_INSTALL_PLUGINDIR ")
    set(in_block FALSE)
    break()
  endif()
endforeach()
if(block STREQUAL "" OR NOT block MATCHES "include\\(cmake/PluginDirGuard.cmake\\)"
   OR NOT block MATCHES "pf_check_plugin_dir\\(")
  message(FATAL_ERROR "the wrapper (${WRAPPER}) does not hold the lines from PF_QT_PLUGIN_DIR to "
                      "KDE_INSTALL_PLUGINDIR through the guard, as this test reads them")
endif()

set(kid "${scratch}/kid")
file(MAKE_DIRECTORY "${kid}/cmake")
configure_file("${GUARD_MODULE}" "${kid}/cmake/PluginDirGuard.cmake" COPYONLY)
file(WRITE "${scratch}/copy.so" "copy\n")
file(WRITE "${kid}/CMakeLists.txt"
"cmake_minimum_required(VERSION 3.22)
project(guardkid LANGUAGES NONE)
include(GNUInstallDirs)
set(QT6_INSTALL_PREFIX \"${scratch}/qt\")
set(QT6_INSTALL_PLUGINS \"plugins\")
set(KDE_INSTALL_FULL_PLUGINDIR \"\${KDE_PLUGINDIR}\")
set(STOCK \"${scratch}/copy.so\")
${block}
file(WRITE \"\${CMAKE_BINARY_DIR}/checked-dir.txt\" \"\${_pf_plugin_dir}\\n\${KDE_INSTALL_PLUGINDIR}\\n\")
install(FILES \"\${STOCK}\" DESTINATION \"\${KDE_INSTALL_PLUGINDIR}/plasma/applets\" RENAME org.kde.plasma.notifications.so)
")

# Whether DESTINATION is one of the stand-ins for Qt's plugin directory or inside it. This is
# the test's own reading of an already evaluated path, not the guard's.
function(pf_is_inside_qt destination out)
  set(hit FALSE)
  foreach(qt_dir IN ITEMS "${scratch}/qt/plugins" "${scratch}/usr/lib64/qt6/plugins")
    string(REGEX REPLACE "([.\\^$*+?()|\[\]])" "\\\\${CMAKE_MATCH_1}" pattern "${qt_dir}")
    if(destination STREQUAL qt_dir OR destination MATCHES "^${pattern}/")
      set(hit TRUE)
    endif()
  endforeach()
  set(${out} ${hit} PARENT_SCOPE)
endfunction()

# The stock plugin's stand-in must be the same file after every install.
set(stock_before "")
file(READ "${scratch}/qt/plugins/${stock_file}" stock_before)

# what|how the directory is given|value|verdict|the words a refusal must have
set(configures
  "the default|none||allows|"
  "Qt's directory, typed PATH|-DPF_NOTIFICATIONS_PLUGIN_DIR:PATH=${qt}|${qt}|stops|${stock}"
  "Qt's directory through a link, typed PATH|-DPF_NOTIFICATIONS_PLUGIN_DIR:PATH=${scratch}/link|${scratch}/link|stops|${stock}"
  "a generator expression, untyped|-DPF_NOTIFICATIONS_PLUGIN_DIR=${scratch}/$<1:qt/plugins>|${scratch}/$<1:qt/plugins>|stops|${chars}"
  "a generator expression, typed PATH|-DPF_NOTIFICATIONS_PLUGIN_DIR:PATH=${scratch}/$<1:qt/plugins>|${scratch}/$<1:qt/plugins>|stops|${chars}"
  "backslashes, typed STRING|-DPF_NOTIFICATIONS_PLUGIN_DIR:STRING=${scratch}<bs>qt<bs>plugins|${scratch}<bs>qt<bs>plugins|stops|${chars}"
  "a leading ~, typed STRING|-DPF_NOTIFICATIONS_PLUGIN_DIR:STRING=<tilde>/qtplugins|<tilde>/qtplugins|stops|a leading ~"
  # A list separator cannot be given on the command line (CMake splits it there): through an
  # initial cache only.
  "a list separator, from an initial cache as STRING|cache-string:${scratch}/a<semi>b|${scratch}/a<semi>b|stops|${chars}"
  "backslashes, from an initial cache as STRING|cache-string:${scratch}<bs>qt<bs>plugins|${scratch}<bs>qt<bs>plugins|stops|${chars}"
  "a generator expression, from an initial cache as INTERNAL|cache-internal:${scratch}/$<1:qt/plugins>|${scratch}/$<1:qt/plugins>|stops|${chars}"
  "Qt's directory, from an initial cache as INTERNAL|cache-internal:${qt}|${qt}|stops|${stock}"
  "a link to another directory, typed PATH|-DPF_NOTIFICATIONS_PLUGIN_DIR:PATH=${scratch}/alias|${scratch}/alias|allows|"
  "a link to a link to another directory, untyped|-DPF_NOTIFICATIONS_PLUGIN_DIR=${scratch}/chain1|${scratch}/chain1|allows|")

set(number 0)
foreach(case IN LISTS configures)
  math(EXPR number "${number} + 1")
  string(REPLACE "|" ";" fields "${case}")
  list(GET fields 0 what)
  list(GET fields 1 how)
  list(GET fields 2 value)
  list(GET fields 3 verdict)
  list(GET fields 4 words)
  untokenize("${value}" value)
  set(build "${scratch}/build-${number}")
  # With no language enabled GNUInstallDirs cannot choose a library directory; it is given.
set(args "-S" "${kid}" "-B" "${build}" "-DCMAKE_INSTALL_PREFIX=${scratch}/prefix-${number}"
    "-DCMAKE_INSTALL_LIBDIR=lib64")
  if(how MATCHES "^-D")
    untokenize("${how}" how)
    # On a command line a backslash is an escape, as in a cache file.
    string(REPLACE "\\" "\\\\" how "${how}")
    list(APPEND args "${how}")
  elseif(NOT how STREQUAL "none")
    # In a cache file a backslash is written doubled.
    set(cache_value "${value}")
    string(REPLACE "\\" "\\\\" cache_value "${cache_value}")
    if(how STREQUAL "cache-string")
      set(kind STRING)
    else()
      set(kind INTERNAL)
    endif()
    set(initial "${scratch}/initial-${number}.cmake")
    file(WRITE "${initial}" "set(PF_NOTIFICATIONS_PLUGIN_DIR \"${cache_value}\" CACHE ${kind} \"\")\n")
    list(APPEND args "-C" "${initial}")
  endif()
  set(output "")
  execute_process(COMMAND "${CMAKE_COMMAND}" ${args} RESULT_VARIABLE result OUTPUT_VARIABLE output
                  ERROR_VARIABLE output TIMEOUT 60)
  string(REGEX REPLACE "[ \t\r\n]+" " " flat "${output}")
  set(ok FALSE)
  set(why "")
  if(verdict STREQUAL "stops")
    if(NOT result EQUAL 0 AND flat MATCHES "${words}")
      set(ok TRUE)
    else()
      string(APPEND why "the configure did not stop with the guard's words (exit ${result})")
    endif()
    if(EXISTS "${build}/cmake_install.cmake")
      set(ok FALSE)
      string(APPEND why "; an install script was written although the directory had to be refused")
    endif()
  else()
    if(NOT result EQUAL 0)
      string(APPEND why "the configure failed (exit ${result})")
    else()
      # Two lines: the directory the guard resolved, and the one the wrapper hands to install().
      file(READ "${build}/checked-dir.txt" checked)
      string(FIND "${checked}" "\n" _newline)
      string(SUBSTRING "${checked}" 0 ${_newline} resolved)
      math(EXPR _after "${_newline} + 1")
      string(SUBSTRING "${checked}" ${_after} -1 rest)
      string(FIND "${rest}" "\n" _newline)
      string(SUBSTRING "${rest}" 0 ${_newline} installed_as)
      if(resolved STREQUAL "")
        string(APPEND why "the wrapper does not keep the directory the guard resolved;")
      elseif(NOT installed_as STREQUAL resolved)
        string(APPEND why "the wrapper hands install() '${installed_as}', not the directory the guard resolved ('${resolved}'); the file said [${checked}]")
      endif()
      file(READ "${build}/cmake_install.cmake" install_script)
      string(REGEX MATCH "DESTINATION \"[^\"]*\" TYPE FILE" destination "${install_script}")
      string(REGEX REPLACE "^DESTINATION \"(.*)\" TYPE FILE$" "\\1" destination "${destination}")
      if(NOT destination STREQUAL "${resolved}/plasma/applets")
        string(APPEND why "the install script installs to '${destination}', not the directory the guard resolved ('${resolved}/plasma/applets')")
      endif()
      pf_is_inside_qt("${destination}" inside)
      if(inside)
        string(APPEND why "the install script installs to '${destination}', which is Qt's plugin directory or inside it")
      endif()
      string(STRIP "${why}" why)
      if(why STREQUAL "" AND destination STREQUAL "${resolved}/plasma/applets")
        execute_process(COMMAND "${CMAKE_COMMAND}" --install "${build}" RESULT_VARIABLE installed
                        OUTPUT_VARIABLE install_output ERROR_VARIABLE install_output TIMEOUT 60)
        if(NOT installed EQUAL 0)
          set(why "the install failed: ${install_output}")
        elseif(NOT EXISTS "${destination}/org.kde.plasma.notifications.so")
          set(why "the copy is not where the install script said it would go")
        endif()
      endif()
      if(why STREQUAL "")
        set(ok TRUE)
      endif()
    endif()
  endif()
  file(READ "${scratch}/qt/plugins/${stock_file}" stock_now)
  if(NOT stock_now STREQUAL stock_before)
    set(ok FALSE)
    string(APPEND why "; the stand-in for the stock plugin's file was replaced")
  endif()
  if(ok)
    math(EXPR passed "${passed} + 1")
    message(STATUS "PASS ${verdict} (through the wrapper's lines): ${what}")
  else()
    math(EXPR failed "${failed} + 1")
    string(REGEX REPLACE "[ \t\r\n]+" " " why "${why} ${flat}")
    message(STATUS "FAIL ${verdict} (through the wrapper's lines): ${what}: ${why}")
    if(why MATCHES "configure failed" OR why MATCHES "did not stop")
      # The configure's own words, for whoever broke the small project rather than the guard.
      message(STATUS "   the configure said: ${flat}")
    endif()
  endif()
endforeach()

file(REMOVE_RECURSE "${scratch}")

math(EXPR total "${passed} + ${failed}")
message(STATUS "plugin directory guard: ${passed} of ${total} cases")
if(NOT failed EQUAL 0)
  message(FATAL_ERROR "${failed} case(s) of the plugin directory guard failed")
endif()
