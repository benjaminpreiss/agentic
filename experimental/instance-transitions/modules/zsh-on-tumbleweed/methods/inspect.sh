#!/bin/sh
set -eu
path=$1
test -x "$path" && grep -Fqx -- "$path" /etc/shells || { echo 'Declared login shell unavailable' >&2; exit 1; }
