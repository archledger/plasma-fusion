# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# The directory guard of the notification applet copy (CMakeLists.txt). The copy is installed as
# plasma/applets/org.kde.plasma.notifications.so under PF_NOTIFICATIONS_PLUGIN_DIR and must never
# replace the stock plugin's file in Qt's own plugin directory. The functions below decide whether
# a directory is safe for that; tests/guardtest.cmake is their unit test.

# Sets VAR to PATH as the file system resolves it: component by component, a symbolic link is
# replaced by its target, also where the target does not exist yet, and ".." is the parent of what
# was resolved so far. file(REAL_PATH) does not resolve a path that does not exist yet, and
# collapsing ".." first would hide "link/..", which is the parent of the link's target.
function(pf_resolved_path path var)
  cmake_path(ABSOLUTE_PATH path OUTPUT_VARIABLE _absolute)
  string(REPLACE "/" ";" _pending "${_absolute}")
  set(_resolved "/")
  set(_links 0)
  while(TRUE)
    list(LENGTH _pending _left)
    if(_left EQUAL 0)
      break()
    endif()
    list(POP_FRONT _pending _component)
    if(_component STREQUAL "" OR _component STREQUAL ".")
      continue()
    elseif(_component STREQUAL "..")
      cmake_path(GET _resolved PARENT_PATH _resolved)
      continue()
    endif()

    set(_candidate "${_resolved}/${_component}")
    if(IS_SYMLINK "${_candidate}")
      # A loop of links must end somewhere; the file system gives up at 40 as well.
      math(EXPR _links "${_links} + 1")
      if(_links GREATER 40)
        message(FATAL_ERROR "${path}: more than 40 symbolic links")
      endif()
      file(READ_SYMLINK "${_candidate}" _target)
      cmake_path(ABSOLUTE_PATH _target BASE_DIRECTORY "${_resolved}" OUTPUT_VARIABLE _target)
      # The resolution continues from the target, which may hold links and ".." of its own; the
      # components that followed the link stay after it.
      string(REPLACE "/" ";" _target_components "${_target}")
      list(POP_FRONT _target_components _root)
      list(PREPEND _pending ${_target_components})
      set(_resolved "/")
      continue()
    endif()
    set(_resolved "${_candidate}")
  endwhile()
  set(${var} "${_resolved}" PARENT_SCOPE)
endfunction()

# Stops the configuration unless PLUGIN_DIR is safe to install the copy under, with Qt's plugin
# directory in QT_PLUGIN_DIR. It must be an absolute path, and once symbolic links are resolved
# it must be neither that directory nor inside it. The same is checked for PLUGIN_DIR/plasma/applets,
# where the plugin itself lands: that may reach Qt's directory through a link of its own.
function(pf_check_plugin_dir plugin_dir qt_plugin_dir)
  if(NOT IS_ABSOLUTE "${plugin_dir}")
    # install() reads a relative destination against the installation prefix, where a path such as
    # lib64/qt6/plugins is Qt's own plugin directory.
    message(FATAL_ERROR
      "PF_NOTIFICATIONS_PLUGIN_DIR ('${plugin_dir}') must be an absolute path: installed against "
      "the installation prefix it may be Qt's own plugin directory, and the copy would replace the "
      "stock plugin's file")
  endif()

  pf_resolved_path("${plugin_dir}" _resolved)
  pf_resolved_path("${qt_plugin_dir}" _qt)
  pf_resolved_path("${plugin_dir}/plasma/applets" _resolved_applets)
  pf_resolved_path("${qt_plugin_dir}/plasma/applets" _qt_applets)

  # A path is not a prefix of itself, so the two directories being the same is its own test.
  cmake_path(IS_PREFIX _qt "${_resolved}" _inside)
  cmake_path(IS_PREFIX _qt "${_resolved_applets}" _inside_applets)
  if(_resolved STREQUAL _qt OR _inside OR _inside_applets)
    message(FATAL_ERROR
      "PF_NOTIFICATIONS_PLUGIN_DIR ('${plugin_dir}') is Qt's plugin directory or inside it "
      "('${qt_plugin_dir}'), symbolic links resolved: the copy would replace the stock plugin's file")
  endif()
endfunction()
