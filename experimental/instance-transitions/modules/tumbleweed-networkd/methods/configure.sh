#!/bin/sh
# Stage only. NEVER reload/reconfigure networkd from this method.
set -eu
[ "$#" -eq 7 ] || { echo 'expected interpreter, interface, MAC, mode, CIDR, gateway, DNS list' >&2; exit 2; }
python_path=$1
shift
[ "$python_path" = /usr/bin/python3 ] && [ -x "$python_path" ] || {
  echo 'Bound Python 3 interpreter unavailable' >&2; exit 1;
}
[ "$(id -u)" -eq 0 ] || { echo 'Must run as root' >&2; exit 1; }
[ "${AGENTIC_DISPOSABLE_VM:-}" = true ] && [ "${AGENTIC_CONSOLE_VERIFIED:-}" = true ] || {
  echo 'Only stage on a disposable VM with verified console access' >&2; exit 1;
}
grep -Eq '^ID="?opensuse-tumbleweed"?$' /etc/os-release || { echo 'Not openSUSE Tumbleweed' >&2; exit 1; }
systemctl is-active --quiet systemd-networkd.service || { echo 'systemd-networkd is not active; will not switch managers' >&2; exit 1; }
for other in NetworkManager.service wicked.service; do
  if systemctl is-active --quiet "$other"; then echo "Competing network manager active: $other" >&2; exit 1; fi
done
"$python_path" - "$@" <<'PY'
import ipaddress
import os
from pathlib import Path
import re
import sys
import tempfile

iface, mac, mode, address, gateway, dns = sys.argv[1:]
if iface in ('.', '..') or not re.fullmatch(r'[A-Za-z0-9_.:-]+', iface):
    raise SystemExit('invalid interface name')
mac = mac.lower()
if not re.fullmatch(r'(?:[0-9a-f]{2}:){5}[0-9a-f]{2}', mac):
    raise SystemExit('invalid interface MAC')
actual = Path('/sys/class/net', iface, 'address')
if not actual.is_file() or actual.read_text().strip().lower() != mac:
    raise SystemExit('selected interface MAC does not match target')
if mode == 'dhcp':
    if address or gateway or dns.strip():
        raise SystemExit('DHCP must not include static address, gateway or DNS inputs')
    network = '[Network]\nDHCP=ipv4\n'
elif mode == 'static':
    try:
        selected = ipaddress.IPv4Interface(address)
        route = ipaddress.IPv4Address(gateway)
        servers = [ipaddress.IPv4Address(item) for item in dns.split()]
    except ipaddress.AddressValueError as error:
        raise SystemExit(f'invalid static IPv4 input: {error}') from error
    except ipaddress.NetmaskValueError as error:
        raise SystemExit(f'invalid IPv4 prefix: {error}') from error
    if not servers:
        raise SystemExit('at least one static DNS resolver is required')
    network = '[Network]\nDHCP=no\nAddress=' + str(selected) + '\nGateway=' + str(route) + '\n'
    network += ''.join('DNS=' + str(server) + '\n' for server in servers)
else:
    raise SystemExit('network mode must be dhcp or static')

folder = Path('/etc/systemd/network')
path = folder / '10-agentic.network'
if not folder.is_dir() or folder.is_symlink() or path.is_symlink():
    raise SystemExit('networkd directory missing or unsafe symlink')
marker = '# Managed by Agentic; staged only. Do not reload remotely without a recovery plan.\n'
if path.exists() and not path.read_text().startswith(marker):
    raise SystemExit('refusing to overwrite an unmanaged networkd file')
content = marker + '[Match]\nMACAddress=' + mac + '\n\n' + network
# Files in this directory can take effect on an external networkd restart.
# The transition must arrange independent reachability checks before activation.
fd, tmp = tempfile.mkstemp(prefix='.agentic-network.', dir=folder)
try:
    with os.fdopen(fd, 'w') as stream:
        stream.write(content)
        stream.flush()
        os.fsync(stream.fileno())
    os.chmod(tmp, 0o644)
    os.replace(tmp, path)
finally:
    if os.path.exists(tmp):
        os.unlink(tmp)
print(f'Staged {path}; NOT activated. Keep console access and arrange remote verification before reload.')
PY
