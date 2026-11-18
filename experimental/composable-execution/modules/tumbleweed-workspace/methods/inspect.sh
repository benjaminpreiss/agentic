#!/usr/bin/env bash
set -euo pipefail
[[ $# == 1 && "$1" == /* ]] || exit 2
[[ -r /etc/os-release ]] && grep -Eq '^ID="?opensuse-tumbleweed"?$' /etc/os-release || {
  echo 'Requires openSUSE Tumbleweed' >&2; exit 1;
}
test -d "$1"
