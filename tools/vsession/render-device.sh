#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# Select a render device on the host; check it again as the actual test user in the container.
# Usage: render-device.sh auto|software, or render-device.sh --check DEVICE

pfv_render_device() {
  local mode=${1:?mode} root=${2:-/dev} node
  case "$mode" in
    auto)
      for node in "$root"/dri/renderD*; do
        if [[ -c "$node" ]]; then printf '%s\n' "$node"; return 0; fi
      done ;;
    software) ;;
    *) echo 'render-device: expected auto or software' >&2; return 64 ;;
  esac
  if [[ -c "$root/udmabuf" ]]; then printf '%s\n' "$root/udmabuf"; return 0; fi
  echo 'render-device: no suitable render node or software device' >&2
  return 1
}

pfv_check_render_device() {
  local node=${1:?device} fd
  if [[ ! -c "$node" ]]; then echo "render-device: unavailable character device: $node" >&2; return 1; fi
  if ! exec {fd}<>"$node"; then
    echo "render-device: cannot open render device: $node" >&2
    return 1
  fi
  exec {fd}>&-
  echo "PASS: opened render device $node (uid $EUID)"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
  if [[ $# == 1 ]]; then
    pfv_render_device "$1"
  elif [[ $# == 2 && $1 == --check ]]; then
    pfv_check_render_device "$2"
  else
    echo 'usage: render-device.sh auto|software, or --check DEVICE' >&2
    exit 64
  fi
fi
