#!/usr/bin/env bash
# Thin agentic adapter; only the pinned toolkit invokes nixos-anywhere.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
[[ $# == 0 ]] || { echo 'usage: bash scripts/deployment/install.sh' >&2; exit 2; }
[[ -s $ROOT/.deployment/record.json && -s $ROOT/.deployment/generated/machine.nix && -s $ROOT/.deployment/extra-files/etc/agentic/recovery-password-hash ]] || {
  echo 'Missing prepared record, machine facts or recovery password hash' >&2; exit 1;
}
[[ ! -e $ROOT/.deployment/install-receipt.json ]] || { echo 'Existing receipt: do not reinstall' >&2; exit 1; }
rev=$(git -C "$ROOT" rev-parse HEAD)
branch=$(git -C "$ROOT" symbolic-ref --quiet --short HEAD) || { echo 'Install requires a pushed branch' >&2; exit 1; }
report="$ROOT/scripts/deployment/facter.sh"
# Reusing an existing reviewed hardware report must not regenerate it.
if [[ -e $ROOT/.deployment/generated/facter.json ]]; then report=-; fi
echo "Review before the shared toolkit's final typed ERASE confirmation:"
printf '  Commit: %s (branch %s)\n' "$rev" "$branch"
jq -r '"  Target: \(.target)\n  Whole disk: \(.disk.path) [\(.disk.size) bytes] \(.disk.model) \(.disk.serial)\n  Boot/NIC: \(.boot) / \(.nic) \(.mac)"' "$ROOT/.deployment/record.json"
bash "$ROOT/scripts/deployment/toolkit.sh" install \
  "$ROOT/.deployment/record.json" "$ROOT" "$rev" "$ROOT/.deployment/generated" agentic "$branch" \
  "$ROOT/.deployment/install-receipt.json" "$report" "$ROOT/.deployment/extra-files" \
  "$ROOT/scripts/deployment/pre-erase.sh"
