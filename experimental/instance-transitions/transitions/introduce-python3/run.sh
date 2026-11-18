#!/bin/sh
set -eu
test -x /usr/bin/python3 || { echo 'Declared interpreter not installed' >&2; exit 1; }
