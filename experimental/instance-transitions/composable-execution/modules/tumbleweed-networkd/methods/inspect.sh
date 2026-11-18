#!/usr/bin/env bash
set -euo pipefail
[[ $# == 1 && "$1" =~ ^[a-zA-Z0-9_.:-]+$ && "$1" != . && "$1" != .. ]] || exit 2
ip -brief address show dev "$1"
