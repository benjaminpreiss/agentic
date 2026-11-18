#!/bin/sh
set -eu
[ "$#" -eq 1 ] || { echo 'expected package name' >&2; exit 2; }
package=$1
case "$package" in ''|*[!a-zA-Z0-9_.+-]*) echo 'invalid package name' >&2; exit 2 ;; esac
command -v rpm >/dev/null || { echo 'rpm unavailable' >&2; exit 1; }
rpm -q -- "$package"
