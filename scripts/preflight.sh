#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPLOY="$ROOT/.deployment"
[[ -r "$DEPLOY/target.txt" && -r "$DEPLOY/selected-disk.txt" ]] || { echo 'Run bash scripts/prepare.sh first.' >&2; exit 1; }
target="$(<"$DEPLOY/target.txt")"
disk="$(<"$DEPLOY/selected-disk.txt")"
echo "Target: $target"
echo "SELECTED DISK (WILL BE ERASED): $disk"
ssh -o BatchMode=yes "$target" 'set -eu; echo "Running OS:"; cat /etc/os-release | head -3; echo "Disks:"; lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL; echo "Boot firmware:"; if test -d /sys/firmware/efi; then echo UEFI; else echo BIOS; fi; echo "Network:"; ip -brief address; echo "Privilege:"; if test "$(id -u)" = 0 || sudo -n true; then echo ready; else echo "NEEDS PASSWORDLESS SUDO OR ROOT SSH"; exit 1; fi'
echo 'Verify boot firmware, disk size, network interfaces and out-of-band rescue console manually.'
