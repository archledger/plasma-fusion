# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# The directory guard of the notification applet copy (CMakeLists.txt). The copy is installed as
# plasma/applets/org.kde.plasma.notifications.so under PF_NOTIFICATIONS_PLUGIN_DIR and must never
# replace the stock plugin's file in a directory Plasma loads plugins from. The functions below
# decide whether a directory is safe for that and give the directory back as the file system
# resolves it, so that the build installs to the directory it checked; tests/guardtest.cmake is
# their unit test.

# A path is a path to CMake only while it holds none of the characters CMake reads with a meaning
# of its own: a generator expression or a variable reference ($), a list separator (;), list
# brackets ([ and ]) and the escape character (\). install() evaluates a generator expression in a
# destination, turns backslashes into separators and expands a leading ~ to the home directory,
# while cmake_path(ABSOLUTE_PATH) reads that same text as an ordinary name; and the list commands
# used below to walk a path would split it elsewhere. So such a path is refused, whether it is the
# typed value or the target of a link on the way. (Each character is looked for on its own: CMake's
# regular expressions give a backslash no special meaning inside brackets.)
function(pf_assert_plain_path path what)
  foreach(character IN ITEMS ";" "$" "[" "]" "\\")
    string(FIND "${path}" "${character}" _found)
    if(NOT _found EQUAL -1)
      message(FATAL_ERROR
        "${what} ('${path}') holds a character that CMake reads with a meaning of its own "
        "(one of \$ ; [ ] \\): it cannot be checked against what install() would use")
    endif()
  endforeach()
  string(FIND "${path}" "~" _found)
  if(_found EQUAL 0)
    message(FATAL_ERROR
      "${what} ('${path}') has a leading ~, which install() expands to the home directory and a "
      "path check reads as an ordinary name")
  endif()
endfunction()

# Sets VAR to PATH as the file system resolves it: component by component, a symbolic link is
# replaced by its target, also where the target does not exist yet, and ".." is the parent of what
# was resolved so far. file(REAL_PATH) does not resolve a path that does not exist yet, and
# collapsing ".." first would hide "link/..", which is the parent of the link's target. WHAT names
# the path in a refusal.
function(pf_resolved_path path var)
  set(_what "A directory")
  if(ARGC GREATER 2)
    set(_what "${ARGV2}")
  endif()
  pf_assert_plain_path("${path}" "${_what}")
  cmake_path(ABSOLUTE_PATH path OUTPUT_VARIABLE _absolute)
  string(REPLACE "/" ";" _pending "${_absolute}")
  # The path resolved so far, without its leading slash ("" at the root): a component joins to it
  # as "/<so far>/<component>".
  set(_resolved "")
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
      set(_so_far "/${_resolved}")
      cmake_path(GET _so_far PARENT_PATH _parent)
      string(REGEX REPLACE "^/" "" _resolved "${_parent}")
      continue()
    endif()

    set(_candidate "/${_resolved}/${_component}")
    if(IS_SYMLINK "${_candidate}")
      # A loop of links must end somewhere; the file system gives up at 40 as well.
      math(EXPR _links "${_links} + 1")
      if(_links GREATER 40)
        message(FATAL_ERROR "${_what} ('${path}'): more than 40 symbolic links")
      endif()
      file(READ_SYMLINK "${_candidate}" _target)
      pf_assert_plain_path("${_target}" "The target of a symbolic link on the way to ${path}")
      # A relative target is read from the directory that holds the link.
      cmake_path(ABSOLUTE_PATH _target BASE_DIRECTORY "/${_resolved}" OUTPUT_VARIABLE _target)
      # The resolution continues from the target, which may hold links and ".." of its own; the
      # components that followed the link stay after it.
      string(REPLACE "/" ";" _target_components "${_target}")
      list(POP_FRONT _target_components _root)
      list(PREPEND _pending ${_target_components})
      set(_resolved "")
      continue()
    endif()
    string(REGEX REPLACE "^/" "" _resolved "${_candidate}")
  endwhile()
  set(${var} "/${_resolved}" PARENT_SCOPE)
endfunction()

# Stops the configuration unless PLUGIN_DIR is safe to install the copy under, and sets OUT_VAR to
# that directory as the file system resolves it, for the install rule: the string checked is the
# string installed. QT_PLUGIN_DIR is Qt's plugin directory; any further arguments are other
# directories Plasma loads plugins from, such as KDE's own when it is not Qt's (empty ones are
# skipped).
#
# PLUGIN_DIR must be an absolute path. Once symbolic links are resolved, it must be none of those
# directories nor inside any of them; the directory the plugin itself lands in,
# PLUGIN_DIR/plasma/applets, must not be inside any of them either and must not be the stock
# plugin's own directory there, wherever a link to it leads. And the plugin's own path there must
# not be a link: the install would replace the link with the copy.
function(pf_check_plugin_dir plugin_dir qt_plugin_dir out_var)
  if(NOT IS_ABSOLUTE "${plugin_dir}")
    # install() reads a relative destination against the installation prefix, where a path such as
    # lib64/qt6/plugins is Qt's own plugin directory.
    message(FATAL_ERROR
      "PF_NOTIFICATIONS_PLUGIN_DIR ('${plugin_dir}') must be an absolute path: installed against "
      "the installation prefix it may be Qt's own plugin directory, and the copy would replace the "
      "stock plugin's file")
  endif()

  pf_resolved_path("${plugin_dir}" _resolved "PF_NOTIFICATIONS_PLUGIN_DIR")
  pf_resolved_path("${plugin_dir}/plasma/applets" _resolved_applets "PF_NOTIFICATIONS_PLUGIN_DIR/plasma/applets")

  set(_first TRUE)
  foreach(root "${qt_plugin_dir}" ${ARGN})
    if(root STREQUAL "")
      continue()
    endif()
    pf_resolved_path("${root}" _root_resolved "A plugin directory")
    pf_resolved_path("${root}/plasma/applets" _root_applets "A plugin directory/plasma/applets")
    # A path is not a prefix of itself, so the two directories being the same is its own test.
    cmake_path(IS_PREFIX _root_resolved "${_resolved}" _inside)
    cmake_path(IS_PREFIX _root_resolved "${_resolved_applets}" _inside_applets)
    if(_resolved STREQUAL _root_resolved OR _inside OR _inside_applets OR _resolved_applets STREQUAL _root_applets)
      if(_first)
        # The words the unit test and the part page know.
        message(FATAL_ERROR
          "PF_NOTIFICATIONS_PLUGIN_DIR ('${plugin_dir}') is Qt's plugin directory or inside it, or is "
          "the stock plugin's own directory ('${root}'), symbolic links resolved: the copy would "
          "replace the stock plugin's file")
      endif()
      message(FATAL_ERROR
        "PF_NOTIFICATIONS_PLUGIN_DIR ('${plugin_dir}') is another directory Plasma loads plugins "
        "from ('${root}') or inside it, or is the stock plugin's own directory there, symbolic "
        "links resolved: the copy would replace the stock plugin's file")
    endif()
    set(_first FALSE)
  endforeach()

  if(IS_SYMLINK "${_resolved_applets}/org.kde.plasma.notifications.so")
    message(FATAL_ERROR
      "PF_NOTIFICATIONS_PLUGIN_DIR ('${plugin_dir}'): the plugin's own path there is a symbolic "
      "link, and the install would replace the link with the copy")
  endif()

  set(${out_var} "${_resolved}" PARENT_SCOPE)
endfunction()
