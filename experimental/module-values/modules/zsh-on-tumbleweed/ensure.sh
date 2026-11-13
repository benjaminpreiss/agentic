#!/bin/sh
set -eu
path=$1
grep -Eq '^ID="?opensuse-tumbleweed"?$' /etc/os-release || { echo 'Not Tumbleweed' >&2; exit 1; }
zypper -n install zsh
test -f "$path" && test -x "$path" || { echo 'Declared Zsh path is not executable' >&2; exit 1; }
grep -Fqx -- "$path" /etc/shells || { echo 'Declared Zsh path is not a registered login shell' >&2; exit 1; }
