#!/bin/sh
set -eu
name=$1 shell=$2
case "$name" in ''|root|*[!a-z0-9-]*|[!a-z]*) echo 'Invalid unprivileged account name' >&2; exit 1 ;; esac
awk -F: -v name="$name" '$1 == name { found=1 } END { exit !found }' /etc/passwd || {
  echo 'Local account unavailable' >&2; exit 1;
}
entry=$(getent passwd "$name") || { echo 'Account unavailable' >&2; exit 1; }
[ "$(printf '%s\n' "$entry" | cut -d: -f7)" = "$shell" ] || { echo 'Account shell mismatch' >&2; exit 1; }
