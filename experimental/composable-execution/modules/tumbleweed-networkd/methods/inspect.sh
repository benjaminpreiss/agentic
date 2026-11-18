#!/usr/bin/env bash
set -euo pipefail
[[ $# == 1 && "$1" =~ ^[a-zA-Z0-9_.:-]+$ && "$1" != . && "$1" != .. ]] || exit 2
[[ -r /etc/os-release ]] && grep -Eq '^ID="?opensuse-tumbleweed"?$' /etc/os-release || {
  echo 'Requires openSUSE Tumbleweed' >&2; exit 1;
}
ip -brief address show dev "$1"
