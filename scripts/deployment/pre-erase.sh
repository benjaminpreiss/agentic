#!/usr/bin/env bash
# Consumer-specific effective NixOS checks before the shared typed erase gate.
set -euo pipefail
[[ $# == 3 ]] || { echo 'usage: pre-erase.sh STAGED_FLAKE HOST RECORD' >&2; exit 2; }
stage=$1 host=$2 record=$3
expected_disk=$(jq -er .disk.path "$record")
expected_boot=$(jq -er .boot "$record")
expected_mac=$(jq -er .mac "$record")
expected_arch=$(jq -er .arch "$record")
[[ $expected_arch == x86_64 && $expected_boot =~ ^(bios|uefi)$ ]] || { echo 'Unsupported architecture or boot mode' >&2; exit 1; }
flake="path:$stage#nixosConfigurations.$host.config"
nix_eval() { nix --extra-experimental-features 'nix-command flakes' eval --no-write-lock-file "$@"; }
[[ $(nix_eval --raw "$flake.agenticMachine.disk") == "$expected_disk" ]] || { echo 'Disk differs from target record' >&2; exit 1; }
[[ $(nix_eval --raw "$flake.agenticMachine.bootMode") == "$expected_boot" ]] || { echo 'Boot mode differs from target record' >&2; exit 1; }
mac=$(nix_eval --raw "$flake.systemd.network.networks.\"10-agentic\".matchConfig.MACAddress")
[[ $(printf '%s' "$mac" | tr '[:upper:]' '[:lower:]') == $(printf '%s' "$expected_mac" | tr '[:upper:]' '[:lower:]') ]] || { echo 'Effective network MAC differs from target record' >&2; exit 1; }
[[ $(nix_eval --json "$flake.services.openssh.enable") == true ]] || { echo 'SSH disabled' >&2; exit 1; }
if [[ $expected_boot == bios ]]; then
  expected=$(jq -nc --arg disk "$expected_disk" '[$disk]')
  [[ $(nix_eval --json "$flake.boot.loader.grub.devices") == "$expected" ]] || { echo 'GRUB disk differs from target record' >&2; exit 1; }
else
  [[ $(nix_eval --json "$flake.boot.loader.systemd-boot.enable") == true ]] || { echo 'UEFI bootloader disabled' >&2; exit 1; }
fi
# Evaluation of only hostName would not trigger module assertions.
nix_eval --raw "$flake.system.build.toplevel.drvPath" >/dev/null
echo 'Evaluated disk, bootloader, network MAC, SSH and complete system match the record.'
