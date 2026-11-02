#!/usr/bin/env bash
# Agentic-specific machine choices; shared toolkit owns target discovery.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
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
