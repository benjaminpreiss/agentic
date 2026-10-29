#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPLOY="$ROOT/.deployment"
[[ "${1:-}" == --install ]] || { echo "Usage: bash scripts/deploy.sh --install" >&2; exit 2; }
[[ -f "$DEPLOY/generated/machine.nix" ]] || { echo 'Run bash scripts/prepare.sh first.' >&2; exit 1; }
command -v nix >/dev/null || { echo 'Nix required locally. See https://nixos.org/download/' >&2; exit 1; }
"$ROOT/scripts/preflight.sh"
cd "$DEPLOY"
if [[ ! -f flake.lock ]]; then nix --extra-experimental-features 'nix-command flakes' flake lock --flake "path:$DEPLOY"; fi
nix --extra-experimental-features 'nix-command flakes' eval --raw "path:$DEPLOY#nixosConfigurations.agentic.config.networking.hostName"
echo
printf 'DISK ERASE CONFIRMATION: type ERASE-AND-INSTALL-NIXOS: '
IFS= read -r answer </dev/tty
[[ "$answer" == ERASE-AND-INSTALL-NIXOS ]] || { echo 'Cancelled'; exit 1; }
target="$(<"$DEPLOY/target.txt")"
nix --extra-experimental-features 'nix-command flakes' run github:nix-community/nixos-anywhere -- \
  --flake "path:$DEPLOY#agentic" --target-host "$target"
