#!/usr/bin/env bash
# Agentic-specific machine choices; shared toolkit owns target discovery.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
if [[ $# == 0 ]]; then
  # Detect candidates, never choose the disk to erase for the operator.
  [[ -r /dev/tty ]] || { echo 'Interactive terminal required; see --help for arguments' >&2; exit 2; }
  ask() {
    local prompt=$1 default=${2:-} answer
    printf '%s%s: ' "$prompt" "${default:+ [$default]}" >/dev/tty
    IFS= read -r answer </dev/tty
    REPLY=${answer:-$default}
  }
  ask 'Root SSH target (SSH fingerprint must already be verified)'
  target=$REPLY
  [[ $target =~ ^root@[a-zA-Z0-9_.:-]+$ ]] || { echo 'Invalid target' >&2; exit 1; }
  echo 'Whole disks reported by rescue environment (confirm in provider console):'
  ssh -o StrictHostKeyChecking=yes "$target" 'lsblk -d -o PATH,SIZE,TYPE,MODEL,SERIAL'
  ask 'Whole /dev disk to erase (no automatic selection)'
  disk=$REPLY
  host_default=$(ssh -o StrictHostKeyChecking=yes "$target" 'hostname -s')
  ask 'New NixOS hostname' "${host_default:-agentic-node}"
  hostname=$REPLY
  ask 'Local SSH public key file' "$HOME/.ssh/id_ed25519.pub"
  keyfile=$REPLY
  # Only positive DHCP lease evidence provides a default; static remains an
  # explicit choice because public/private IP ranges do not imply DHCP.
  iface=$(ssh -o StrictHostKeyChecking=yes "$target" "ip -4 route show default | awk 'NR==1 {for(i=1;i<=NF;i++) if(\$i==\"dev\") {print \$(i+1);exit}}'")
  mode_default=''
  if [[ $iface =~ ^[a-zA-Z0-9_.:-]+$ ]] &&
    ssh -o StrictHostKeyChecking=yes "$target" "networkctl status '$iface' --no-pager 2>/dev/null" | grep -Eq 'DHCP4 Client ID|DHCP4 Address|DHCP4 via|Address:.*\(DHCP4\)'; then
    mode_default=dhcp
  fi
  ask 'Network mode (dhcp/static; inspect provider routing)' "$mode_default"
  mode=$REPLY
  if [[ $mode == static ]]; then
    ask 'Static IPv4/CIDR'; addr=$REPLY
    ask 'IPv4 gateway'; gateway=$REPLY
    ask 'Comma-separated IPv4 DNS servers'; dns=$REPLY
    exec bash "$ROOT/scripts/deployment/prepare.sh" "$target" "$disk" "$hostname" "$keyfile" "$mode" "$addr" "$gateway" "$dns"
  fi
  exec bash "$ROOT/scripts/deployment/prepare.sh" "$target" "$disk" "$hostname" "$keyfile" "$mode"
fi
[[ $# -ge 5 ]] || { echo 'usage: prepare.sh root@HOST /dev/WHOLE_DISK HOSTNAME SSH_PUBLIC_KEY_FILE dhcp|static [IPv4/CIDR GATEWAY DNS,IPS]' >&2; exit 2; }
target=$1 disk=$2 hostname=$3 keyfile=$4 mode=$5
[[ $target =~ ^root@[a-zA-Z0-9_.:-]+$ && $disk =~ ^/dev/[a-zA-Z0-9_./+-]+$ && $disk != *../* ]] || { echo 'Invalid target/disk' >&2; exit 1; }
[[ $hostname =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$ && -f $keyfile && ! -L $keyfile ]] || { echo 'Invalid hostname/key file' >&2; exit 1; }
[[ $mode == dhcp || $mode == static ]] || { echo 'Network mode must be dhcp or static' >&2; exit 1; }
if [[ $mode == static ]]; then [[ $# == 8 ]] || { echo 'Static mode needs CIDR, gateway and DNS list' >&2; exit 2; }
else [[ $# == 5 ]] || { echo 'DHCP mode takes no address arguments' >&2; exit 2; }; fi
[[ ! -e $ROOT/.deployment && ! -L $ROOT/.deployment ]] || { echo 'Existing .deployment: preserve it; do not prepare over another machine' >&2; exit 1; }
key=$(<"$keyfile")
[[ $key =~ ^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp256|sk-ssh-ed25519@openssh.com)[[:space:]][a-zA-Z0-9+/=]+ ]] || { echo 'Invalid SSH public key' >&2; exit 1; }
umask 077
mkdir -m 700 "$ROOT/.deployment"
# Failure leaves a private, incomplete record for inspection; never retry by
# overwriting it or by running the disk installer.
bash "$ROOT/scripts/deployment/toolkit.sh" discover "$target" "$disk" "$ROOT/.deployment/record.json"
record="$ROOT/.deployment/record.json"
[[ $(jq -r .arch "$record") == x86_64 && $(jq -r .boot "$record") =~ ^(uefi|bios)$ ]] || { echo 'Unsupported architecture or boot mode' >&2; exit 1; }
valid_ipv4() { local ip=$1 octet; [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1; local IFS=.; for octet in $ip; do [[ $octet =~ ^(0|[1-9][0-9]{0,2})$ ]] && (( 10#$octet <= 255 )) || return 1; done; }
if [[ $mode == static ]]; then
  [[ $6 == */* && ${6#*/} =~ ^[0-9]{1,2}$ ]] && (( 10#${6#*/} <= 32 )) && valid_ipv4 "${6%/*}" && valid_ipv4 "$7" || { echo 'Invalid CIDR/gateway' >&2; exit 1; }
  dns='['; IFS=, read -r -a servers <<<"$8"
  [[ ${#servers[@]} -gt 0 ]] || { echo 'DNS required' >&2; exit 1; }
  for server in "${servers[@]}"; do valid_ipv4 "$server" || { echo 'Invalid DNS' >&2; exit 1; }; dns+=" $(jq -Rn --arg value "$server" '$value')"; done
  dns+=' ]'
else dns='[]'; fi
quoted() { jq -Rn --arg value "$1" '$value'; }
mkdir -m 700 "$ROOT/.deployment/generated"
{
  echo '{ ... }: { agenticMachine = {'
  printf 'hostname = %s;\n' "$(quoted "$hostname")"
  printf 'disk = %s;\n' "$(quoted "$disk")"
  printf 'bootMode = %s;\n' "$(quoted "$(jq -r .boot "$record")")"
  printf 'networkInterface = %s;\n' "$(quoted "$(jq -r .nic "$record")")"
  printf 'networkMAC = %s;\n' "$(quoted "$(jq -r .mac "$record")")"
  printf 'networkMode = %s;\n' "$(quoted "$mode")"
  printf 'sshKey = %s;\n' "$(quoted "$key")"
  if [[ $mode == static ]]; then
    printf 'staticIPv4 = %s; gatewayIPv4 = %s; dnsServers = %s;\n' "$(quoted "$6")" "$(quoted "$7")" "$dns"
  fi
  echo '}; }'
} > "$ROOT/.deployment/generated/machine.nix"
echo 'Private record prepared. Review it against the provider console; set the console recovery password before install.'
