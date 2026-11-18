#!/bin/sh
set -eu
[ "$#" -eq 1 ] || { echo 'expected reviewed package name' >&2; exit 2; }
# This prototype only authorizes the dependency used by tumbleweed-networkd.
[ "$1" = python3 ] || { echo 'package is not in the reviewed prototype allowlist' >&2; exit 2; }
[ "$(id -u)" -eq 0 ] || { echo 'Must run as root' >&2; exit 1; }
[ "${AGENTIC_DISPOSABLE_VM:-}" = true ] && [ "${AGENTIC_CONSOLE_VERIFIED:-}" = true ] || {
  echo 'Disposable VM and console confirmation required' >&2; exit 1;
}
grep -Eq '^ID="?opensuse-tumbleweed"?$' /etc/os-release || { echo 'Not Tumbleweed' >&2; exit 1; }
command -v zypper >/dev/null || { echo 'zypper unavailable' >&2; exit 1; }
zypper --non-interactive install --no-recommends python3
rpm -q -- python3
