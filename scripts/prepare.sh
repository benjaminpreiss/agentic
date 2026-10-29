#!/usr/bin/env bash
# Interactive, local-only generator for a machine-specific NixOS flake.
# Compatible with the Bash 3.2 shipped with macOS.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
OUTPUT="$ROOT/.deployment"

usage() { echo 'Usage: bash scripts/prepare.sh [--output .deployment|relative-subdirectory]' >&2; exit 2; }
if [[ $# -gt 0 ]]; then
  [[ $# -eq 2 && "$1" == --output ]] || usage
  [[ "$2" =~ ^[A-Za-z0-9._/-]+$ && "$2" != /* && "$2" != .. && "$2" != ../* && "$2" != */../* && "$2" != */.. ]] || { echo 'Unsafe output path' >&2; exit 1; }
  OUTPUT="$ROOT/$2"
fi
[[ ! -e "$OUTPUT" ]] || { echo "Output already exists: $OUTPUT (keep it as a backup or remove it before reconfiguring)" >&2; exit 1; }
command -v ssh >/dev/null || { echo 'ssh is required' >&2; exit 1; }
[[ -r /dev/tty ]] || { echo 'An interactive terminal is required' >&2; exit 1; }

ask() {
  local label="$1" default="${2:-}" answer
  if [[ -n "$default" ]]; then
    printf '%s [%s]: ' "$label" "$default" > /dev/tty
  else
    printf '%s: ' "$label" > /dev/tty
  fi
  IFS= read -r answer < /dev/tty || exit 1
  REPLY="${answer:-$default}"
}
fail() { printf 'Invalid value: %s\n' "$1" >&2; exit 1; }
# Nix double-quoted string: escape backslash, quotes, interpolation and control characters.
nix_quote() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//\$/\\\$}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '"%s"' "$s"
}
valid_ipv4() {
  local value="$1" a b c d extra oct
  [[ "$value" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  IFS=. read -r a b c d extra <<< "$value"
  for oct in "$a" "$b" "$c" "$d"; do
    [[ ${#oct} -le 3 && ( "$oct" == 0 || "$oct" != 0* ) ]] || return 1
    (( 10#$oct <= 255 )) || return 1
  done
}

printf '%s\n' 'Prepare an Agentic NixOS installation (no remote changes).'
ask 'Existing SSH target (root@host or passwordless-sudo user@host)'
TARGET="$REPLY"
[[ "$TARGET" =~ ^[A-Za-z_][A-Za-z0-9_.-]*@[A-Za-z0-9_.:-]+$ ]] || fail 'SSH target'
ask 'New NixOS hostname' 'agentic-node'
HOSTNAME_NEW="$REPLY"
[[ "$HOSTNAME_NEW" =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,62}$ ]] || fail 'hostname'
ask 'Full install disk (prefer /dev/disk/by-id/...)'
DISK="$REPLY"
[[ "$DISK" == /dev/* && "$DISK" != *[[:space:]]* && "$DISK" =~ ^/dev/[A-Za-z0-9_./+-]+$ && "$DISK" != *../* ]] || fail 'disk device'
ask 'Boot mode (uefi/bios)'
BOOT="$REPLY"
[[ "$BOOT" == uefi || "$BOOT" == bios ]] || fail 'boot mode'
ask 'Path to your local SSH public key (e.g. ~/.ssh/id_ed25519.pub)'
KEY_PATH="$REPLY"
[[ "$KEY_PATH" == '~/'* ]] && KEY_PATH="$HOME/${KEY_PATH#\~/}"
[[ -r "$KEY_PATH" ]] || fail 'unreadable public key file'
SSH_KEY="$(cat "$KEY_PATH")"
[[ "$SSH_KEY" != *$'\n'* && "$SSH_KEY" =~ ^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp256|sk-ssh-ed25519@openssh.com)[[:space:]][A-Za-z0-9+/=]+([[:space:]].*)?$ ]] || fail 'SSH public key format'
ask 'SSH port after install' '22'
PORT="$REPLY"
[[ "$PORT" =~ ^[0-9]{1,5}$ ]] && (( 10#$PORT >= 1 && 10#$PORT <= 65535 )) || fail 'SSH port'
PORT=$((10#$PORT))
ask 'Network mode (dhcp/static)' 'dhcp'
NETWORK="$REPLY"
[[ "$NETWORK" == dhcp || "$NETWORK" == static ]] || fail 'network mode'
ask 'Interface name (blank matches en*/eth*/ens*)' ''
IFACE="$REPLY"
[[ -z "$IFACE" || "$IFACE" =~ ^[A-Za-z0-9_.:-]+$ ]] || fail 'interface name'
ADDR='' GATEWAY='' DNS_NIX=''
if [[ "$NETWORK" == static ]]; then
  [[ -n "$IFACE" ]] || fail 'static networking requires an exact interface'
  ask 'IPv4 address with CIDR (e.g. 192.0.2.10/24)'
  ADDR="$REPLY"
  [[ "$ADDR" == */* ]] || fail 'IPv4 CIDR'
  valid_ipv4 "${ADDR%/*}" || fail 'IPv4 address'
  PREFIX="${ADDR#*/}"
  [[ "$PREFIX" =~ ^[0-9]{1,2}$ ]] && (( 10#$PREFIX <= 32 )) || fail 'IPv4 prefix'
  ask 'IPv4 default gateway'
  GATEWAY="$REPLY"
  valid_ipv4 "$GATEWAY" || fail 'IPv4 gateway'
  ask 'Comma-separated DNS IPv4 servers (e.g. 1.1.1.1,9.9.9.9)'
  DNS="$REPLY"
  [[ -n "$DNS" ]] || fail 'DNS servers'
  IFS=, read -ra SERVERS <<< "$DNS"
  for server in "${SERVERS[@]}"; do
    server="${server//[[:space:]]/}"
    valid_ipv4 "$server" || fail 'DNS IPv4 server'
    DNS_NIX="$DNS_NIX $(nix_quote "$server")"
  done
fi

# Stage files in a private directory, then move into place.
umask 077
STAGE="$(mktemp -d "$ROOT/.deployment.stage.XXXXXX")"
trap 'rm -rf -- "$STAGE"' EXIT
cp "$ROOT/flake.nix" "$STAGE/flake.nix"
cp -R "$ROOT/modules" "$STAGE/modules"
mkdir -p "$STAGE/generated"
{
  printf '{ ... }: {\n  agenticMachine = {\n'
  printf '    hostname = %s;\n' "$(nix_quote "$HOSTNAME_NEW")"
  printf '    disk = %s;\n' "$(nix_quote "$DISK")"
  printf '    bootMode = %s;\n' "$(nix_quote "$BOOT")"
  printf '    sshKey = %s;\n' "$(nix_quote "$SSH_KEY")"
  printf '    sshPort = %s;\n' "$PORT"
  printf '    networkMode = %s;\n' "$(nix_quote "$NETWORK")"
  printf '    networkInterface = %s;\n' "$(nix_quote "$IFACE")"
  printf '    staticIPv4 = %s;\n' "$(nix_quote "$ADDR")"
  printf '    gatewayIPv4 = %s;\n' "$(nix_quote "$GATEWAY")"
  printf '    dnsServers = [%s ];\n' "$DNS_NIX"
  printf '  };\n}\n'
} > "$STAGE/generated/machine.nix"
printf '%s\n' "$TARGET" > "$STAGE/target.txt"
printf '%s\n' "$DISK" > "$STAGE/selected-disk.txt"
mv "$STAGE" "$OUTPUT"
trap - EXIT
printf '\nPrepared: %s\nNext: bash scripts/preflight.sh && bash scripts/deploy.sh --install\nWARNING: deployment will ERASE the selected disk.\n' "$OUTPUT"
