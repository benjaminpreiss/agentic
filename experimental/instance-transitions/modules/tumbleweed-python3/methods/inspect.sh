#!/bin/sh
set -eu
[ "$#" -eq 1 ] || { echo 'expected declared Python interpreter path' >&2; exit 2; }
path=$1
[ "$path" = /usr/bin/python3 ] && [ -x "$path" ] || { echo 'Declared Python 3 interpreter unavailable' >&2; exit 1; }
"$path" -c 'import sys; assert sys.version_info.major == 3; print(sys.version.split()[0])'
