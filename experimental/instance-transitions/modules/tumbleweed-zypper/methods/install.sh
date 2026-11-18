#!/bin/sh
set -eu
[ "$#" -eq 1 ] || { echo 'expected package name' >&2; exit 2; }
case "$1" in ''|[!a-zA-Z0-9]*|*[!a-zA-Z0-9+._-]*) echo 'Invalid package name' >&2; exit 2 ;; esac
[ "$(id -u)" -eq 0 ] || { echo 'Must run as root' >&2; exit 1; }
[ "${AGENTIC_DISPOSABLE_VM:-}" = true ] && [ "${AGENTIC_CONSOLE_VERIFIED:-}" = true ] || {
  echo 'Disposable VM and console confirmation required' >&2; exit 1;
}
grep -Eq '^ID="?opensuse-tumbleweed"?$' /etc/os-release || { echo 'Not Tumbleweed' >&2; exit 1; }
command -v zypper >/dev/null || { echo 'zypper unavailable' >&2; exit 1; }
zypper --non-interactive install --no-recommends "$1"
rpm -q -- "$1"
