#!/usr/bin/env bash
set -euo pipefail
[[ $# == 1 && "$1" == /* ]] || exit 2
test -d "$1"
