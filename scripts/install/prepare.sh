#!/usr/bin/env bash
# macOS Bash 3.2 compatible. Read-only remote discovery.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
OUT="$ROOT/.deployment"
[[ ! -e "$OUT" ]] || { echo "Existing $OUT. Move or delete it to prepare another machine." >&2; exit 1; }
command -v ssh >/dev/null || { echo 'ssh is required' >&2; exit 1; }
[[ -r /dev/tty ]] || { echo 'Interactive TTY required' >&2; exit 1; }
ask() { local reply; printf '%s [%s]: ' "$1" "${2:-}" >/dev/tty; IFS= read -r reply </dev/tty; REPLY="${reply:-${2:-}}"; }
fail() { echo "STOP: $*" >&2; exit 1; }
nixquote() { local s="$1"; s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//\$/\\\$}"; s="${s//$'\n'/\\n}"; printf '"%s"' "$s"; }
valid_ipv4() { local ip="$1" a b c d v; [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1; IFS=. read -r a b c d <<<"$ip"; for v in "$a" "$b" "$c" "$d"; do [[ "$v" =~ ^(0|[1-9][0-9]{0,2})$ ]] || return 1; (( 10#$v <= 255 )) || return 1; done; }
valid_cidr() { local addr="${1%/*}" p="${1#*/}"; [[ "$1" == */* && "$p" =~ ^[0-9]{1,2}$ ]] && (( 10#$p <= 32 )) && valid_ipv4 "$addr"; }

printf 'Agentic NixOS remote discovery (read-only)\n'
ask 'SSH target (existing configured alias or user@host)'
TARGET="$REPLY"
[[ "$TARGET" =~ ^[A-Za-z0-9_.@:-]+$ && "$TARGET" != -* ]] || fail 'Invalid SSH target'
# Accept standard SSH aliases, usernames and SSH configs; no eval or shell interpolation.
DISC="$(mktemp "${TMPDIR:-/tmp}/agentic-discovery.XXXXXX")"
trap 'rm -f "$DISC"' EXIT
ssh -o BatchMode=yes -o ConnectTimeout=12 "$TARGET" 'bash -s' <<'REMOTE' > "$DISC" 
set -euo pipefail
printf 'ARCH=%s\n' "$(uname -m)"
printf 'HOST=%s\n' "$(hostname -s)"
if [[ -d /sys/firmware/efi ]]; then echo 'BOOT=uefi'; else echo 'BOOT=bios'; fi
printf 'DISKS_BEGIN\n'
lsblk -dnpo NAME,SIZE,TYPE,MODEL | grep ' disk ' || true
printf 'DISKS_END\n'
printf 'ROOT_SOURCE=%s\n' "$(findmnt -n -o SOURCE / || true)"
printf 'ROOT_PARENT=%s\n' "$(lsblk -no PKNAME "$(findmnt -n -o SOURCE /)" 2>/dev/null | head -1 || true)"
printf 'ROUTE4=%s\n' "$(ip -4 route show default | head -1 || true)"
printf 'ROUTE6=%s\n' "$(ip -6 route show default | head -1 || true)"
printf 'DNS=%s\n' "$(resolvectl dns 2>/dev/null | head -1 || true)"
# Is the default-link address leased? State ambiguity explicitly.
iface="$(ip -4 route show default | awk 'NR==1 {for(i=1;i<=NF;i++) if($i=="dev") {print $(i+1);exit}}')"
printf 'IFACE=%s\n' "$iface"
if [[ -n "$iface" ]]; then
  mac="$(cat "/sys/class/net/$iface/address")"
  printf 'MAC=%s\n' "$mac"
  ip -4 -o addr show dev "$iface" | awk '$3=="inet" {print "IPV4=" $4; exit}'
  networkctl status "$iface" --no-pager 2>/dev/null | grep -E 'DHCP4 Client ID|DHCP4 Address|DHCP4 via|Address:.*\(DHCP4\)' | head -1 | sed 's/^/DHCP_EVIDENCE=/' || true
fi
if [[ "$(id -u)" == 0 ]] || sudo -n true 2>/dev/null; then echo 'PRIV=ok'; else echo 'PRIV=no'; fi
REMOTE
readvalue() { sed -n "s/^$1=//p" "$DISC" | head -1; }
ARCH="$(readvalue ARCH)"; [[ "$ARCH" == x86_64 ]] || fail "Unsupported target architecture: $ARCH (flake currently targets x86_64-linux)"
[[ "$(readvalue PRIV)" == ok ]] || fail 'Target requires root SSH or passwordless sudo; do not deploy yet'
BOOT="$(readvalue BOOT)"; HOST="$(readvalue HOST)"; IFACE="$(readvalue IFACE)"; MAC="$(readvalue MAC)"
ROUTE="$(readvalue ROUTE4)"; IPV4="$(readvalue IPV4)"
printf '\nRemote disks:\n'; sed -n '/^DISKS_BEGIN$/,/^DISKS_END$/p' "$DISC" | sed '1d;$d'
ROOT_PARENT="$(readvalue ROOT_PARENT)"
[[ -n "$ROOT_PARENT" ]] && echo "Current root parent: /dev/$ROOT_PARENT"
ask 'Whole disk to ERASE (confirm device from list)' "${ROOT_PARENT:+/dev/$ROOT_PARENT}"
DISK="$REPLY"; [[ "$DISK" == /dev/* && "$DISK" =~ ^/dev/[A-Za-z0-9_./+-]+$ && "$DISK" != *../* ]] || fail 'Invalid disk path'
# Disk must exist as a whole-disk block device, not partition. Do not silently select.
ssh -o BatchMode=yes "$TARGET" 'bash -s' -- "$DISK" <<'REMOTE' >/dev/null || fail 'Selected device is not a whole disk on the target'
set -eu
disk="$1"
[[ -b "$disk" && "$(lsblk -dn -o TYPE "$disk")" == disk ]]
REMOTE
ask 'New NixOS hostname' "${HOST:-agentic-node}"; HOST="$REPLY"
[[ "$HOST" =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,62}$ ]] || fail 'Invalid hostname'
ask 'Boot mode (confirm detected)' "$BOOT"; BOOT="$REPLY"
[[ "$BOOT" == bios || "$BOOT" == uefi ]] || fail 'Invalid boot mode'
ask 'Network interface (confirm detected)' "$IFACE"; IFACE="$REPLY"
[[ "$IFACE" =~ ^[A-Za-z0-9_.:-]+$ ]] || fail 'Network interface is required'
[[ "$MAC" =~ ^([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}$ ]] || fail 'Could not discover a valid MAC address'
printf 'Default-route interface: %s; MAC: %s\n' "$IFACE" "$MAC"
# DHCP is guessed only when positive evidence exists, not based on a private/public IP.
if grep -q '^DHCP_EVIDENCE=' "$DISC"; then DEFAULT_NETWORK=dhcp; else DEFAULT_NETWORK=static; fi
printf 'Default route: %s\n' "${ROUTE:-none}"
printf 'Current address: %s\n' "${IPV4:-none}"
printf 'Network choice requires confirmation. Cloud static/IPv6 routing may need custom configuration.\n'
ask 'Network mode (dhcp/static)' "$DEFAULT_NETWORK"; NET="$REPLY"
[[ "$NET" == dhcp || "$NET" == static ]] || fail 'Invalid network mode'
ADDR='' GATEWAY='' DNS_LIST=''
if [[ "$NET" == static ]]; then
  [[ -n "$IPV4" ]] || fail 'No IPv4 detected for safe static configuration'
  ask 'Static IPv4/CIDR' "$IPV4"; ADDR="$REPLY"; valid_cidr "$ADDR" || fail 'Invalid CIDR'
  DEF_GW="$(printf '%s\n' "$ROUTE" | awk '{for(i=1;i<=NF;i++)if($i=="via") {print $(i+1);exit}}')"
  ask 'IPv4 gateway' "$DEF_GW"; GATEWAY="$REPLY"; valid_ipv4 "$GATEWAY" || fail 'Invalid IPv4 gateway'
  ask 'Comma-separated IPv4 DNS resolvers' '1.1.1.1,9.9.9.9'; DNS="$REPLY"
  OLDIFS="$IFS"; IFS=,; for item in $DNS; do valid_ipv4 "$item" || fail "Invalid DNS $item"; DNS_LIST="$DNS_LIST $(nixquote "$item")"; done; IFS="$OLDIFS"
fi
# Prefer existing SSH key but permit selection.
DEFAULT_KEY="$HOME/.ssh/id_ed25519.pub"
[[ -r "$DEFAULT_KEY" ]] || DEFAULT_KEY=''
ask 'Local SSH public key file' "$DEFAULT_KEY"; KEY="$REPLY"
[[ "$KEY" == '~/'* ]] && KEY="$HOME/${KEY#\~/}"
[[ -r "$KEY" ]] || fail 'SSH public key file not readable'
SSH_KEY="$(cat "$KEY")"
[[ "$SSH_KEY" != *$'\n'* && "$SSH_KEY" =~ ^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp256|sk-ssh-ed25519@openssh.com)[[:space:]][A-Za-z0-9+/=]+ ]] || fail 'Invalid public key'
ask 'NixOS SSH port' '22'; PORT="$REPLY"
[[ "$PORT" =~ ^[0-9]{1,5}$ ]] && (( 10#$PORT >= 1 && 10#$PORT <= 65535 )) || fail 'Invalid SSH port'
PORT=$((10#$PORT))

umask 077
STAGE="$(mktemp -d "$ROOT/.deployment.stage.XXXXXX")"
trap 'rm -rf "$STAGE"; rm -f "$DISC"' EXIT
bash "$ROOT/scripts/stage.sh" "$STAGE"
mkdir -p "$STAGE/generated"
{
  echo '{ ... }: { agenticMachine = {'
  printf 'hostname = %s;\n' "$(nixquote "$HOST")"
  printf 'disk = %s;\n' "$(nixquote "$DISK")"
  printf 'bootMode = %s;\n' "$(nixquote "$BOOT")"
  printf 'sshKey = %s;\n' "$(nixquote "$SSH_KEY")"
  printf 'sshPort = %s;\n' "$PORT"
  printf 'networkMode = %s;\n' "$(nixquote "$NET")"
  printf 'networkInterface = %s;\n' "$(nixquote "$IFACE")"
  printf 'networkMAC = %s;\n' "$(nixquote "$MAC")"
  printf 'staticIPv4 = %s;\n' "$(nixquote "$ADDR")"
  printf 'gatewayIPv4 = %s;\n' "$(nixquote "$GATEWAY")"
  printf 'dnsServers = [%s ];\n' "$DNS_LIST"
  echo '}; }'
} > "$STAGE/generated/machine.nix"
printf '%s\n' "$TARGET" > "$STAGE/target.txt"
printf '%s\n' "$DISK" > "$STAGE/selected-disk.txt"
printf '%s\n' "$BOOT" > "$STAGE/boot-mode.txt"
printf '%s\n' "$IFACE" > "$STAGE/network-interface.txt"
printf '%s\n' "$MAC" > "$STAGE/network-mac.txt"
printf '%s\n' "$NET" > "$STAGE/network-mode.txt"
printf '%s\n' "$ARCH" > "$STAGE/architecture.txt"
mv "$STAGE" "$OUT"
trap - EXIT
rm -f "$DISC"
printf '\nGenerated %s\nNext: bash scripts/install/recovery-password.sh, then bash scripts/install/preflight.sh\nThen: bash scripts/install/deploy.sh --install\nDISK WILL BE ERASED. Copy backups off server first.\n' "$OUT"
