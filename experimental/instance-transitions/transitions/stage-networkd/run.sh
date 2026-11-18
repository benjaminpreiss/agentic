#!/bin/sh
set -eu
# The module method following this script stages a config file. It never reloads networking.
printf '%s\n' 'Checking the bound OS and Python runtime before staging networkd config.'
