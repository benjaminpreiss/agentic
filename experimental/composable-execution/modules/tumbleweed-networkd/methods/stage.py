#!/usr/bin/env python3
"""Stage a Tumbleweed systemd-networkd file. Never reload or activate networking."""

import ipaddress
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import tempfile

MARKER = '# Managed by Agentic; staged only. Do not reload remotely without recovery.\n'
NETWORK_DIR = Path('/etc/systemd/network')
NETWORK_FILE = '10-agentic.network'


def render(interface_name, network_mac, mode, static_ipv4, gateway_ipv4, dns_servers):
    """Validate declarative inputs and return deterministic, inert networkd text."""
    if (interface_name in ('.', '..')
            or not re.fullmatch(r'[A-Za-z0-9_.:-]+', interface_name)):
        raise ValueError('invalid interface name')
    mac = network_mac.lower()
    if not re.fullmatch(r'(?:[0-9a-f]{2}:){5}[0-9a-f]{2}', mac):
        raise ValueError('invalid interface MAC')
    if mode == 'dhcp':
        if static_ipv4 or gateway_ipv4 or dns_servers.strip():
            raise ValueError('DHCP must not include static IPv4, gateway or DNS')
        network = '[Network]\nDHCP=ipv4\n'
    elif mode == 'static':
        try:
            address = ipaddress.IPv4Interface(static_ipv4)
            gateway = ipaddress.IPv4Address(gateway_ipv4)
            resolvers = [ipaddress.IPv4Address(item) for item in dns_servers.split()]
        except ValueError as error:
            raise ValueError('invalid static IPv4, gateway or DNS') from error
        if not resolvers:
            raise ValueError('at least one static DNS resolver is required')
        network = ('[Network]\nDHCP=no\nAddress=' + str(address) + '\nGateway='
                   + str(gateway) + '\n')
        network += ''.join('DNS=' + str(server) + '\n' for server in resolvers)
    else:
        raise ValueError('network mode must be dhcp or static')
    return (MARKER + '[Match]\nName=' + interface_name + '\nMACAddress=' + mac
            + '\n\n' + network)


def require_target(interface_name, network_mac, *, os_release=Path('/etc/os-release'),
                   net_dir=Path('/sys/class/net'), is_active=None):
    """Check live preconditions on the machine where this artifact is invoked."""
    if not re.search(r'^ID="?opensuse-tumbleweed"?$', os_release.read_text(), re.M):
        raise ValueError('target does not identify as openSUSE Tumbleweed')
    actual_mac = (net_dir / interface_name / 'address').read_text().strip().lower()
    if actual_mac != network_mac.lower():
        raise ValueError('selected interface MAC does not match target')
    if is_active is None:
        def is_active(unit):
            return subprocess.run(['systemctl', 'is-active', '--quiet', unit],
                                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                  check=False).returncode == 0
    if not is_active('systemd-networkd.service'):
        raise ValueError('systemd-networkd is not active; refusing to switch managers')
    for unit in ('NetworkManager.service', 'wicked.service'):
        if is_active(unit):
            raise ValueError(f'competing network manager active: {unit}')


def stage_file(folder, content):
    """Write a staged file atomically; never replace a non-Agentic configuration."""
    if folder.is_symlink() or not folder.is_dir() or folder.stat().st_mode & 0o022:
        raise ValueError('networkd directory missing, linked or writable by others')
    path = folder / NETWORK_FILE
    if path.is_symlink():
        raise ValueError('refusing linked networkd file')
    if path.exists():
        if not stat.S_ISREG(path.stat().st_mode):
            raise ValueError('refusing non-regular networkd file')
        with path.open(encoding='utf-8') as current:
            if current.read(len(MARKER)) != MARKER:
                raise ValueError('refusing to overwrite unmanaged networkd file')
    fd, temp = tempfile.mkstemp(prefix='.agentic-network.', dir=folder)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as output:
            output.write(content)
            output.flush()
            os.fchmod(output.fileno(), 0o644)
            os.fsync(output.fileno())
        os.replace(temp, path)
        dir_fd = os.open(folder, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try:
            os.fsync(dir_fd)
        finally:
            os.close(dir_fd)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)
    return path


def main(args):
    if len(args) != 6:
        raise ValueError('expected interface, MAC, mode, CIDR, gateway and DNS list')
    content = render(*args)
    require_target(args[0], args[1])
    path = stage_file(NETWORK_DIR, content)
    print(f'Staged {path}; NOT activated. Arrange independent reachability checks before reload.')


if __name__ == '__main__':
    try:
        main(sys.argv[1:])
    except (ValueError, OSError) as error:
        raise SystemExit(str(error)) from error
