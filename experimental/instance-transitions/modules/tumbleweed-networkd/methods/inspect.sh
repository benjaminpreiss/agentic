#!/bin/sh
# Read-only observation. A local route does NOT prove remote SSH reachability.
set -eu
[ "$#" -eq 2 ] || { echo 'expected interface name and MAC' >&2; exit 2; }
iface=$1 expected_mac=$2
case "$iface" in ''|.|..|*[!a-zA-Z0-9_.:-]*) echo 'Invalid interface name' >&2; exit 2 ;; esac
[ -r "/sys/class/net/$iface/address" ] || { echo 'Interface not found' >&2; exit 1; }
actual_mac=$(tr '[:upper:]' '[:lower:]' < "/sys/class/net/$iface/address")
expected_mac=$(printf '%s' "$expected_mac" | tr '[:upper:]' '[:lower:]')
[ "$actual_mac" = "$expected_mac" ] || { echo 'Interface MAC changed' >&2; exit 1; }
command -v ip >/dev/null && command -v networkctl >/dev/null || { echo 'Missing network inspection tools' >&2; exit 1; }
networkctl status "$iface" --no-pager
ip -brief address show dev "$iface"
ip -4 route show default
