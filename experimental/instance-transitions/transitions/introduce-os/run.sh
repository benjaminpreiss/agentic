#!/bin/sh
set -eu
[ "$(id -u)" -eq 0 ] || { echo 'Must run as root on a disposable VM' >&2; exit 1; }
[ "${AGENTIC_DISPOSABLE_VM:-}" = true ] && [ "${AGENTIC_CONSOLE_VERIFIED:-}" = true ] || {
  echo 'Confirm disposable VM and console access before running' >&2; exit 1;
}
grep -Eq '^ID="?opensuse-tumbleweed"?$' /etc/os-release || { echo 'Not Tumbleweed' >&2; exit 1; }
test -r /etc/shells && test -f /etc/shells || { echo 'Missing /etc/shells' >&2; exit 1; }
getent passwd root >/dev/null || { echo 'NSS passwd lookup unavailable' >&2; exit 1; }
command -v zypper >/dev/null || { echo 'zypper unavailable' >&2; exit 1; }
