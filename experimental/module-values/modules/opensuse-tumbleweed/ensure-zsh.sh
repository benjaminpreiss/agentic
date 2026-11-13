#!/bin/sh
set -eu
path=$1
[ "$path" = /usr/bin/zsh ] || { echo 'Wrong path for Tumbleweed Zsh implementation' >&2; exit 1; }
zypper -n install zsh
test -f "$path" && test -x "$path" || { echo 'Declared Zsh path is not executable' >&2; exit 1; }
grep -Fqx -- "$path" /etc/shells || { echo 'Declared Zsh path is not a registered login shell' >&2; exit 1; }
