#!/usr/bin/env python3
"""Prepare a machine-specific, local NixOS deployment directory. Never touches target disk."""
import argparse
import ipaddress
import json
import pathlib
import re
import shutil
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]


def ask(label, default=None):
    prompt = f'{label}' + (f' [{default}]' if default else '') + ': '
    answer = input(prompt).strip()
    return answer or default or ''


def nix_string(value):
    return json.dumps(value)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--output', default='.deployment', help='Local output (ignored by git)')
    args = ap.parse_args()
    output = (ROOT / args.output).resolve()
    if output == ROOT or ROOT not in output.parents:
        sys.exit('Output must be a subdirectory of this repository')
    if output.exists():
        sys.exit(f'{output} already exists; remove it manually to reconfigure')
    print('Prepare an Agentic NixOS installation. No remote changes will occur.')
    target = ask('Existing SSH target (root@host or passwordless-sudo user@host)')
    if not re.fullmatch(r'[a-zA-Z_][a-zA-Z0-9_.-]*@[a-zA-Z0-9_.:-]+', target):
        sys.exit('Invalid SSH target')
    hostname = ask('New NixOS hostname', 'agentic-node')
    if not re.fullmatch(r'[a-zA-Z0-9][a-zA-Z0-9-]{0,62}', hostname):
        sys.exit('Invalid hostname')
    disk = ask('Full install disk (prefer /dev/disk/by-id/...)')
    if not disk.startswith('/dev/') or any(c.isspace() for c in disk):
        sys.exit('Expected an absolute /dev/... disk device')
    boot = ask('Boot mode (uefi/bios)')
    if boot not in ('uefi','bios'):
        sys.exit('Boot mode must be uefi or bios')
    key_path = pathlib.Path(ask('Path to your local SSH public key (e.g. ~/.ssh/id_ed25519.pub)')).expanduser()
    key = key_path.read_text().strip()
    if not re.fullmatch(r'(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp256|sk-ssh-ed25519@openssh.com) [A-Za-z0-9+/=]+(?: .*)?', key):
        sys.exit('Unexpected public key format')
    port = int(ask('SSH port after install', '22'))
    if not 1 <= port <= 65535:
        sys.exit('Invalid SSH port')
    network = ask('Network mode (dhcp/static)', 'dhcp')
    if network not in ('dhcp','static'):
        sys.exit('Network mode must be dhcp or static')
    iface = ask('Interface name (blank matches en*/eth*/ens*)', '')
    addr = gateway = ''
    dns = []
    if network == 'static':
        if not iface: sys.exit('Static IP requires an exact network interface name')
        addr = ask('IPv4 address in CIDR form (e.g. 192.0.2.10/24)')
        gateway = ask('IPv4 default gateway')
        dns = ask('Comma-separated DNS servers (e.g. 1.1.1.1,9.9.9.9)').split(',')
        ipaddress.IPv4Interface(addr)
        ipaddress.IPv4Address(gateway)
        dns = [str(ipaddress.ip_address(item.strip())) for item in dns if item.strip()]
        if not dns: sys.exit('Static configuration requires DNS servers')
    machine = '''{ ... }: {
  agenticMachine = {
%s
  };
}
''' % '\n'.join('    %s = %s;' % (k,nix_string(v) if not isinstance(v,list) and not isinstance(v,int) else (str(v) if isinstance(v,int) else '[ ' + ' '.join(map(nix_string,v)) + ' ]')) for k,v in {
        'hostname': hostname, 'disk':disk, 'bootMode': boot,
        'sshKey':key,'sshPort':port,'networkMode': network,
        'networkInterface':iface,'staticIPv4':addr,'gatewayIPv4':gateway,'dnsServers':dns
    }.items())
    output.mkdir(parents=True)
    shutil.copy2(ROOT / 'flake.nix',output/'flake.nix')
    shutil.copytree(ROOT / 'modules', output/'modules')
    (output/'generated').mkdir()
    (output/'generated'/'machine.nix').write_text(machine)
    (output/'target.txt').write_text(target+'\n')
    (output/'selected-disk.txt').write_text(disk+'\n')
    print(f'Prepared: {output}')
    print('Next: bash scripts/preflight.sh then bash scripts/deploy.sh --install')
    print('WARNING: deployment will ERASE the selected disk.')

if __name__ == '__main__':
    main()
