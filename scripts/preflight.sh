#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DEPLOY="$ROOT/.deployment"
for f in target.txt selected-disk.txt boot-mode.txt network-interface.txt network-mode.txt network-mac.txt architecture.txt generated/machine.nix; do
  [[ -s "$DEPLOY/$f" ]] || { echo "Missing $DEPLOY/$f; rerun prepare.sh" >&2; exit 1; }
done
target="$(cat "$DEPLOY/target.txt")"; disk="$(cat "$DEPLOY/selected-disk.txt")"
boot="$(cat "$DEPLOY/boot-mode.txt")"; iface="$(cat "$DEPLOY/network-interface.txt")"
arch="$(cat "$DEPLOY/architecture.txt")"
mac="$(cat "$DEPLOY/network-mac.txt")"
[[ -s "$DEPLOY/extra-files/etc/agentic/recovery-password-hash" ]] || { echo "Missing recovery password hash; run bash scripts/recovery-password.sh" >&2; exit 1; }
echo "Target: $target"
echo "ERASE DISK: $disk"
echo "Expected boot mode: $boot | interface: $iface | architecture: $arch"
# Parameters are transported as fixed positional arguments; no shell interpolation.
ssh -o BatchMode=yes -o ConnectTimeout=12 "$target" 'bash -s' -- "$disk" "$boot" "$iface" "$arch" "$mac" <<'REMOTE'
set -euo pipefail
disk="$1" boot="$2" iface="$3" arch="$4" mac="$5"
[[ "$(uname -m)" == "$arch" ]] || { echo 'Architecture changed'; exit 1; }
if [[ -d /sys/firmware/efi ]]; then current=uefi; else current=bios; fi
[[ "$current" == "$boot" ]] || { echo 'Boot mode differs from prepared configuration'; exit 1; }
[[ -b "$disk" && "$(lsblk -dn -o TYPE "$disk")" == disk ]] || { echo 'Selected target is not a whole disk'; exit 1; }
ip link show "$iface" >/dev/null 2>&1 || { echo 'Configured network interface not present'; exit 1; }
actual_mac="$(cat "/sys/class/net/$iface/address")"
[[ "${actual_mac,,}" == "${mac,,}" ]] || { echo "Network MAC changed: expected $mac; got $actual_mac"; exit 1; }
if [[ "$(id -u)" != 0 ]]; then sudo -n true || { echo 'Root SSH or passwordless sudo required'; exit 1; }; fi
echo 'Disk verification:'; lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS "$disk"
echo 'Current network:'; ip -brief address show "$iface"; ip route show default
[[ -n "$(ip -4 route show default)" ]] || { echo 'No IPv4 default route; custom networking review required'; exit 1; }
REMOTE
command -v nix >/dev/null || { echo 'Nix missing on local machine' >&2; exit 1; }
# Pin dependencies in the private deployment directory before evaluation.
[[ -f "$DEPLOY/flake.lock" ]] || nix --extra-experimental-features 'nix-command flakes' flake lock "path:$DEPLOY"
# nix eval works before facter.json has been generated
nix --extra-experimental-features 'nix-command flakes' eval --raw "path:$DEPLOY#nixosConfigurations.agentic.config.networking.hostName"
echo
# Validate the *effective* bootloader targets, not just the disk module source.
# NixOS merges options from all modules, which can silently duplicate GRUB devices.
if [[ "$boot" == bios ]]; then
  echo 'Validating effective GRUB installation targets...'
  grub_devices="$(nix --extra-experimental-features 'nix-command flakes' eval --json "path:$DEPLOY#nixosConfigurations.agentic.config.boot.loader.grub.devices")"
  expected_devices="$(printf '["%s"]' "$disk")"
  [[ "$grub_devices" == "$expected_devices" ]] || {
    printf 'ERROR: GRUB devices must be exactly %s; got %s\n' "$expected_devices" "$grub_devices" >&2
    exit 1
  }
fi
# Crucial: evaluating only hostName does NOT check the system assertions.
# Evaluating the toplevel derivation triggers NixOS module assertions before Disko runs.
echo 'Validating complete NixOS system derivation (no build)...'
nix --extra-experimental-features 'nix-command flakes' eval --raw \
  "path:$DEPLOY#nixosConfigurations.agentic.config.system.build.toplevel.drvPath" >/dev/null || {
  echo 'ERROR: NixOS system evaluation failed. Deployment blocked before disk formatting.' >&2
  exit 1
}
echo 'NixOS system evaluation passed.'
echo 'Validating effective networkd match, address, gateway and SSH...'
net="path:$DEPLOY#nixosConfigurations.agentic.config.systemd.network.networks.\"10-agentic\""
match_mac="$(nix eval --raw "$net.matchConfig.MACAddress")"
[[ "${match_mac,,}" == "${mac,,}" ]] || { echo "Effective MAC mismatch ($match_mac != $mac)" >&2; exit 1; }
nix eval --json "path:$DEPLOY#nixosConfigurations.agentic.config.services.openssh.enable" | grep -qx true
mode="$(cat "$DEPLOY/network-mode.txt")"
if [[ "$mode" == static ]]; then
  source_ip="$(sed -n 's/^[[:space:]]*staticIPv4 = "\([^"]*\)";.*/\1/p' "$DEPLOY/generated/machine.nix")"
  source_gw="$(sed -n 's/^[[:space:]]*gatewayIPv4 = "\([^"]*\)";.*/\1/p' "$DEPLOY/generated/machine.nix")"
  addresses="$(nix eval --json "$net.addresses")"
  routes="$(nix eval --json "$net.routes")"
  [[ "$addresses" == *"$source_ip"* && "$routes" == *"$source_gw"* ]] || { echo 'Effective static IP/gateway missing; aborting.' >&2; exit 1; }
fi
echo 'Preflight checks passed, but static IP, IPv6, custom gateways and provider routing still require review.' 
echo 'Off-server backups, out-of-band rescue access and a disposable VM test are strongly recommended.'
