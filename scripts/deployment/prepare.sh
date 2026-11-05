#!/usr/bin/env bash
# Agentic-owned machine/network choices. moss owns the plan and disk install.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
if [[ $# == 0 ]]; then
  [[ -r /dev/tty ]] || { echo 'Interactive terminal required; see usage for non-interactive input' >&2; exit 2; }
  ask() {
    local prompt=$1 default=${2:-} answer
    printf '%s%s: ' "$prompt" "${default:+ [$default]}" >/dev/tty
    IFS= read -r answer </dev/tty
    REPLY=${answer:-$default}
  }
  ask 'Root SSH target (verify fingerprint through provider console first)'; target=$REPLY
  [[ $target =~ ^root@[a-zA-Z0-9_.:-]+$ ]] || { echo 'Invalid SSH target' >&2; exit 1; }
  echo 'Whole disks on rescue target (confirm against provider console):'
  ssh -o StrictHostKeyChecking=yes "$target" 'lsblk -d -o PATH,SIZE,TYPE,MODEL,SERIAL'
  ask 'Whole /dev disk to erase (never chosen automatically)'; disk=$REPLY
  host_default=$(ssh -o StrictHostKeyChecking=yes "$target" 'hostname -s')
  ask 'New NixOS hostname' "${host_default:-agentic-node}"; hostname=$REPLY
  ask 'Local SSH public key file' "$HOME/.ssh/id_ed25519.pub"; keyfile=$REPLY
  iface=$(ssh -o StrictHostKeyChecking=yes "$target" "ip -4 route show default | awk 'NR==1 {for(i=1;i<=NF;i++) if(\$i==\"dev\") {print \$(i+1);exit}}'")
  mode_default=''
  if [[ $iface =~ ^[a-zA-Z0-9_.:-]+$ ]] &&
    ssh -o StrictHostKeyChecking=yes "$target" "networkctl status '$iface' --no-pager 2>/dev/null" | grep -Eq 'DHCP4 Client ID|DHCP4 Address|DHCP4 via|Address:.*\(DHCP4\)'; then
    mode_default=dhcp
  fi
  ask 'Network mode (dhcp/static; review provider routing)' "$mode_default"; mode=$REPLY
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
[[ $target =~ ^root@[a-zA-Z0-9_.:-]+$ && $disk =~ ^/dev/[a-zA-Z0-9_./+-]+$ && $disk != *../* ]] || { echo 'Invalid SSH target/disk' >&2; exit 1; }
[[ $hostname =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$ && -f $keyfile && ! -L $keyfile ]] || { echo 'Invalid hostname/key file' >&2; exit 1; }
[[ $mode == dhcp || $mode == static ]] || { echo 'Network mode must be dhcp or static' >&2; exit 1; }
if [[ $mode == static ]]; then [[ $# == 8 ]] || { echo 'Static mode needs CIDR, gateway and DNS list' >&2; exit 2; }
else [[ $# == 5 ]] || { echo 'DHCP mode takes no address arguments' >&2; exit 2; }; fi
[[ ! -e $ROOT/.deployment && ! -L $ROOT/.deployment ]] || { echo 'Existing .deployment: do not overwrite another machine' >&2; exit 1; }
key=$(<"$keyfile")
[[ $key =~ ^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp256|sk-ssh-ed25519@openssh.com)[[:space:]][a-zA-Z0-9+/=]+ ]] || { echo 'Invalid SSH public key' >&2; exit 1; }
valid_ipv4() { local ip=$1 octet; [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1; local IFS=.; for octet in $ip; do [[ $octet =~ ^(0|[1-9][0-9]{0,2})$ ]] && (( 10#$octet <= 255 )) || return 1; done; }
if [[ $mode == static ]]; then
  [[ $6 == */* && ${6#*/} =~ ^[0-9]{1,2}$ ]] && (( 10#${6#*/} <= 32 )) && valid_ipv4 "${6%/*}" && valid_ipv4 "$7" || { echo 'Invalid CIDR/gateway' >&2; exit 1; }
  dns='['; IFS=, read -r -a servers <<<"$8"
  [[ ${#servers[@]} -gt 0 ]] || { echo 'DNS required' >&2; exit 1; }
  for server in "${servers[@]}"; do valid_ipv4 "$server" || { echo 'Invalid DNS' >&2; exit 1; }; dns+=" $(jq -Rn --arg value "$server" '$value')"; done
  dns+=' ]'
else dns='[]'; fi
# Read-only facts needed by agentic's machine.nix. The moss plan will re-probe
# and verify the selected disk, boot and NIC before any destructive action.
raw=$(ssh -o StrictHostKeyChecking=yes "$target" 'set -eu; uname -m; if test -d /sys/firmware/efi; then echo uefi; else echo bios; fi; ip -j route show default')
arch=$(printf '%s\n' "$raw" | head -n 1)
boot=$(printf '%s\n' "$raw" | head -n 2 | tail -n 1)
routes=$(printf '%s\n' "$raw" | tail -n +3)
[[ $arch == x86_64 && $boot =~ ^(uefi|bios)$ ]] || { echo 'Unsupported architecture/boot mode' >&2; exit 1; }
iface=$(jq -er 'if length == 1 then .[0].dev else error("ambiguous default route") end' <<<"$routes")
[[ $iface =~ ^[a-zA-Z0-9_.:-]+$ ]] || { echo 'Invalid NIC' >&2; exit 1; }
mac=$(ssh -o StrictHostKeyChecking=yes "$target" "cat /sys/class/net/$iface/address")
[[ $mac =~ ^([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}$ ]] || { echo 'Invalid MAC' >&2; exit 1; }
[[ $(ssh -o StrictHostKeyChecking=yes "$target" "test -b '$disk' && lsblk -dn -o TYPE '$disk'") == disk ]] || { echo 'Target is not a whole disk' >&2; exit 1; }
# Operator-local, ignored storage is owned by moss. Neither config nor plan is
# written into the Nix store or committed source.
umask 077
bash "$ROOT/scripts/deployment/toolkit.sh" init
[[ ! -e $ROOT/.moss/$target/machine.json && ! -L $ROOT/.moss/$target/machine.json ]] || { echo 'Existing moss machine config: do not overwrite' >&2; exit 1; }
mkdir -m 700 "$ROOT/.deployment"
mkdir -m 700 "$ROOT/.deployment/generated"
mkdir -p "$ROOT/.deployment/extra-files"
quoted() { jq -Rn --arg value "$1" '$value'; }
{
  echo '{ ... }: { agenticMachine = {'
  printf 'hostname = %s; disk = %s; bootMode = %s;\n' "$(quoted "$hostname")" "$(quoted "$disk")" "$(quoted "$boot")"
  printf 'networkInterface = %s; networkMAC = %s; networkMode = %s;\n' "$(quoted "$iface")" "$(quoted "$mac")" "$(quoted "$mode")"
  printf 'sshKey = %s;\n' "$(quoted "$key")"
  if [[ $mode == static ]]; then
    printf 'staticIPv4 = %s; gatewayIPv4 = %s; dnsServers = %s;\n' "$(quoted "$6")" "$(quoted "$7")" "$dns"
  fi
  echo '}; }'
} > "$ROOT/.deployment/generated/machine.nix"
rev=$(git -C "$ROOT" rev-parse HEAD)
branch=$(git -C "$ROOT" symbolic-ref --quiet --short HEAD) || { echo 'A pushed branch is required' >&2; exit 1; }
mkdir -p -m 700 "$ROOT/.moss/$target/plans"
# Store agentic-specific paths once. The public CLI alone owns plans/receipts.
config="$ROOT/.moss/$target/machine.json"
jq -n --arg repo "$ROOT" --arg rev "$rev" --arg branch "$branch" --arg machine "$ROOT/.deployment/generated" \
  --arg receipt "$ROOT/.moss/$target/install-receipt.json" --arg disk "$disk" \
  --arg report "$ROOT/scripts/deployment/facter.sh" --arg recovery "$ROOT/.deployment/extra-files" \
  --arg check "$ROOT/scripts/deployment/pre-erase.sh" \
  '{version:1,repo:$repo,revision:$rev,branch:$branch,output:"agentic",machine:$machine,receipt:$receipt,
    remoteCheckout:"/var/lib/agentic/source",remoteMachine:"/var/lib/agentic/machine",
    remoteState:"/var/lib/agentic/deployment",disk:$disk,
    reportGenerator:$report,recoveryDir:$recovery,preEraseCheck:$check}' > "$config"
chmod 600 "$config"
echo "Prepared private $config and .deployment/generated/machine.nix. Review them and set the recovery password before planning."
