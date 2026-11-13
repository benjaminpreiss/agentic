#!/usr/bin/env bash
# Read-only Tumbleweed hardware and service inventory for a fresh, disposable VM.
# Run on the target. Save the report privately; it can include MACs and serials.
set -euo pipefail
if ! grep -q '^ID="\?opensuse-tumbleweed"\?$' /etc/os-release; then
  echo 'Requires openSUSE Tumbleweed; refusing to infer hardware from another OS' >&2
  exit 1
fi
section() { printf '\n===== %s =====\n' "$1"; }
section 'OS and kernel'
grep -E '^(ID|VERSION_ID|PRETTY_NAME)=' /etc/os-release
uname -a
section 'boot / root / disks'
findmnt / /boot /boot/efi 2>/dev/null || true
lsblk -o NAME,TYPE,FSTYPE,MOUNTPOINTS
section 'loaded kernel modules (observation, NOT a safe removal list)'
lsmod
section 'hardware to driver bindings'
if command -v lspci >/dev/null 2>&1; then lspci -nnk; else echo 'lspci unavailable; install pciutils to collect PCI bindings'; fi
if command -v lsusb >/dev/null 2>&1; then lsusb; else echo 'lsusb unavailable; install usbutils to collect USB devices'; fi
section 'network'
ip -br link
ip -br addr
ip route
section 'initramfs modules (if dracut tooling available)'
if command -v lsinitrd >/dev/null 2>&1; then
  lsinitrd -m || echo 'Could not inspect current initramfs'
else
  echo 'lsinitrd unavailable; initramfs driver dependencies remain unknown'
fi
section 'installed kernel and firmware packages'
rpm -qa 'kernel*' '*firmware*' | sort
section 'enabled systemd services and sockets'
systemctl list-unit-files --state=enabled --type=service,socket --no-pager
section 'required operator checks'
echo 'Confirm out-of-band console, boot after reboot, SSH/network, disk, and backup recovery.'
echo 'Unloaded modules can still be required during early boot, for recovery, or by future hardware.'
echo 'No driver, firmware, package, or service was removed.'
