#!/usr/bin/env bash
set -euo pipefail
# A reviewed transition supplies the package; an external executor must enforce its policy.
[[ $# == 1 && "$1" =~ ^[a-zA-Z0-9][a-zA-Z0-9+._-]*$ ]] || {
  echo 'Invalid package name' >&2; exit 2;
}
[[ -r /etc/os-release ]] && grep -Eq '^ID="?opensuse-tumbleweed"?$' /etc/os-release || {
  echo 'Requires openSUSE Tumbleweed' >&2; exit 1;
}
zypper --non-interactive install --no-recommends "$1"
rpm -q -- "$1"
