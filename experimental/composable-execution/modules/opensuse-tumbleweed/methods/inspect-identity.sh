#!/usr/bin/env bash
set -euo pipefail
[[ $# == 0 ]] || exit 2
[[ -r /etc/os-release ]] || { echo 'OS identity unavailable' >&2; exit 1; }
grep -Eq '^ID="?opensuse-tumbleweed"?$' /etc/os-release || {
  echo 'Target does not identify as openSUSE Tumbleweed' >&2; exit 1;
}
printf '%s\n' 'Target currently identifies as openSUSE Tumbleweed'
