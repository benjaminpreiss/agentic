#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DEPLOY="$ROOT/.deployment"
[[ -f "$DEPLOY/flake.nix" && -f "$DEPLOY/generated/machine.nix" && -f "$DEPLOY/generated/facter.json" ]] || { echo 'Missing prepared deployment files or facter.json' >&2; exit 1; }
TARGET="${TARGET:-$(cat "$DEPLOY/target.txt")}"; HOST="${TARGET#*@}"
[[ -n "$HOST" ]] || exit 1
cp "$ROOT/flake.nix" "$DEPLOY/flake.nix"
cp "$ROOT/modules/agentic.nix" "$DEPLOY/modules/agentic.nix"
cd "$DEPLOY"
echo 'Refreshing pinned Nix inputs (new packages require a rebuild)...'
nix flake lock "path:$DEPLOY"
echo 'Evaluating NixOS closure...'
nix eval --raw "path:$DEPLOY#nixosConfigurations.agentic.config.system.build.toplevel.drvPath" >/dev/null
printf 'Build and switch on root@%s? [y/N] ' "$HOST" > /dev/tty
IFS= read -r answer < /dev/tty
[[ "$answer" == y || "$answer" == Y ]] || exit 1
nix run nixpkgs#nixos-rebuild -- switch --flake "path:$DEPLOY#agentic" --target-host "root@$HOST" --build-host "root@$HOST"
echo 'Activated. Reconnect and verify pi, nono, herdr, and the agentic services.'
