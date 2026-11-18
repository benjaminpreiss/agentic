#!/bin/sh
set -eu
command -v zypper >/dev/null || { echo 'Tumbleweed zypper unavailable' >&2; exit 1; }
