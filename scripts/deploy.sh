#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DEPLOY="$ROOT/.deployment"
[[ "${1:-}" == --install && $# -eq 1 ]] || { echo 'Usage: bash scripts/deploy.sh --install' >&2; exit 2; }
bash "$ROOT/scripts/preflight.sh"
target="$(cat "$DEPLOY/target.txt")"; disk="$(cat "$DEPLOY/selected-disk.txt")"
echo
echo "DANGER: nixos-anywhere WILL ERASE $disk on $target."
echo 'Existing Ubuntu, user data and on-disk backups will be destroyed.'
printf 'Type ERASE-AND-INSTALL-NIXOS to continue: ' > /dev/tty
IFS= read -r confirmation < /dev/tty
[[ "$confirmation" == ERASE-AND-INSTALL-NIXOS ]] || { echo 'Cancelled'; exit 1; }
cd "$DEPLOY"
# The generated facter report is saved locally and consumed on subsequent builds.
# This reports hardware; it does not replace explicit networking/disk choices.
nix --extra-experimental-features 'nix-command flakes' run github:nix-community/nixos-anywhere -- \
  --flake "path:$DEPLOY#agentic" \
  --generate-hardware-config nixos-facter "$DEPLOY/generated/facter.json" \
  --extra-files "$DEPLOY/extra-files" \
  --target-host "$target"
echo 'Installation command completed. Verify SSH access and the generated hardware report.'
