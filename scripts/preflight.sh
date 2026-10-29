#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DEPLOY="$ROOT/.deployment"
for f in target.txt selected-disk.txt boot-mode.txt network-interface.txt network-mode.txt architecture.txt generated/machine.nix; do
  [[ -s "$DEPLOY/$f" ]] || { echo "Missing $DEPLOY/$f; rerun prepare.sh" >&2; exit 1; }
done
target="$(cat "$DEPLOY/target.txt")"; disk="$(cat "$DEPLOY/selected-disk.txt")"
boot="$(cat "$DEPLOY/boot-mode.txt")"; iface="$(cat "$DEPLOY/network-interface.txt")"
arch="$(cat "$DEPLOY/architecture.txt")"
echo "Target: $target"
echo "ERASE DISK: $disk"
echo "Expected boot mode: $boot | interface: $iface | architecture: $arch"
# Parameters are transported as fixed positional arguments; no shell interpolation.
ssh -o BatchMode=yes -o ConnectTimeout=12 "$target" 'bash -s' -- "$disk" "$boot" "$iface" "$arch" <<'REMOTE'
set -euo pipefail
disk="$1" boot="$2" iface="$3" arch="$4"
[[ "$(uname -m)" == "$arch" ]] || { echo 'Architecture changed'; exit 1; }
if [[ -d /sys/firmware/efi ]]; then current=uefi; else current=bios; fi
[[ "$current" == "$boot" ]] || { echo 'Boot mode differs from prepared configuration'; exit 1; }
[[ -b "$disk" && "$(lsblk -dn -o TYPE "$disk")" == disk ]] || { echo 'Selected target is not a whole disk'; exit 1; }
ip link show "$iface" >/dev/null 2>&1 || { echo 'Configured network interface not present'; exit 1; }
if [[ "$(id -u)" != 0 ]]; then sudo -n true || { echo 'Root SSH or passwordless sudo required'; exit 1; }; fi
echo 'Disk verification:'; lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS "$disk"
echo 'Current network:'; ip -brief address show "$iface"; ip route show default
[[ -n "$(ip -4 route show default)" ]] || { echo 'No IPv4 default route; custom networking review required'; exit 1; }
REMOTE
command -v nix >/dev/null || { echo 'Nix missing on local machine' >&2; exit 1; }
# Pin dependencies in the private deployment directory before evaluation.
[[ -f "$DEPLOY/flake.lock" ]] || nix --extra-experimental-features 'nix-command flakes' flake lock --flake "path:$DEPLOY"
# nix eval works before facter.json has been generated
nix --extra-experimental-features 'nix-command flakes' eval --raw "path:$DEPLOY#nixosConfigurations.agentic.config.networking.hostName"
echo
echo 'Preflight checks passed, but static IP, IPv6, custom gateways and provider routing still require review.'
echo 'Off-server backups, out-of-band rescue access and a disposable VM test are strongly recommended.'
