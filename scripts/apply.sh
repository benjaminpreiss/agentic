#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DEPLOY="$ROOT/.deployment"
[[ -f "$DEPLOY/flake.nix" ]] || { echo 'Missing .deployment/flake.nix: run prepare first' >&2; exit 1; }
[[ -f "$DEPLOY/generated/machine.nix" ]] || { echo 'Missing generated machine settings' >&2; exit 1; }
[[ -f "$DEPLOY/generated/facter.json" ]] || { echo 'Missing facter.json: copy it from the successful install' >&2; exit 1; }
TARGET="${TARGET:-$(cat "$DEPLOY/target.txt")}" 
# The install target may be a former Ubuntu user. Connect to the new NixOS root via the same host.
HOST="${TARGET#*@}"
[[ -n "$HOST" ]] || { echo 'Empty target host' >&2; exit 1; }
cp "$ROOT/modules/agentic.nix" "$DEPLOY/modules/agentic.nix"
cp "$ROOT/modules/base.nix" "$DEPLOY/modules/base.nix"
cd "$DEPLOY"
echo 'Evaluating complete NixOS derivation locally...'
nix eval --raw "path:$DEPLOY#nixosConfigurations.agentic.config.system.build.toplevel.drvPath" >/dev/null
printf 'About to rebuild the existing NixOS installation on %s (no disk formatting).\nContinue? [y/N] ' "$HOST" > /dev/tty
IFS= read -r confirm < /dev/tty
[[ "$confirm" == y || "$confirm" == Y ]] || exit 1
# Build and activate on the target, avoiding the aarch64-darwin -> x86_64-linux build mismatch.
nix run nixpkgs#nixos-rebuild -- \
  switch --flake "path:$DEPLOY#agentic" \
  --target-host "root@$HOST" --build-host "root@$HOST"
echo 'NixOS configuration switched. Reconnect to verify shell and status.'
