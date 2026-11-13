#!/bin/sh
set -eu
shell=$1
path=$2
case "$shell" in
  zsh) package=zsh ;;
  *) echo 'Unsupported shell on Tumbleweed' >&2; exit 1 ;;
esac
zypper -n install "$package"
test -f "$path" && test -x "$path" || { echo 'Declared Zsh path is not executable' >&2; exit 1; }
grep -Fqx -- "$path" /etc/shells || { echo 'Declared Zsh path is not a registered login shell' >&2; exit 1; }
