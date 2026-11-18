#!/usr/bin/env bash
set -euo pipefail
# Illustrative reviewed method artifact. Only the external executor may authorize execution.
zypper --non-interactive install --no-recommends python3
rpm -q python3
