#!/bin/sh
set -eu
shell_id=$1
path=$2
case "$shell_id" in
  zsh) [ "$path" = /usr/bin/zsh ] || { echo 'Path differs from declared Tumbleweed shell location' >&2; exit 1; } ;;
  *) echo 'Unsupported login shell' >&2; exit 1 ;;
esac
zypper -n install "$shell_id"
test -f "$path" && test -x "$path" || { echo 'Declared Zsh path is not executable' >&2; exit 1; }
grep -Fqx -- "$path" /etc/shells || { echo 'Declared Zsh path is not a registered login shell' >&2; exit 1; }
