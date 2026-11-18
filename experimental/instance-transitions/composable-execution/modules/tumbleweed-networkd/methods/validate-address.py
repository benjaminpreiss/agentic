#!/usr/bin/env python3
"""Validate the declared address. Staging/activation is NOT implemented here."""
import ipaddress
import sys

if len(sys.argv) != 2:
    raise SystemExit('expected one IPv4/CIDR input')
print(ipaddress.IPv4Interface(sys.argv[1]))
