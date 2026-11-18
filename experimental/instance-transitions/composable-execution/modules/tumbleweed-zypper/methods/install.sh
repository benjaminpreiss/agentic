#!/usr/bin/env bash
set -euo pipefail
# A reviewed transition supplies the package; an external executor must enforce its policy.
[[ $# == 1 && "$1" =~ ^[a-zA-Z0-9][a-zA-Z0-9+._-]*$ ]] || {
  echo 'Invalid package name' >&2; exit 2;
}
zypper --non-interactive install --no-recommends "$1"
rpm -q -- "$1"
