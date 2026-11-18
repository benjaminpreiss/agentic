#!/bin/sh
set -eu
grep -Eq '^ID="?opensuse-tumbleweed"?$' /etc/os-release || { echo 'Not openSUSE Tumbleweed' >&2; exit 1; }
