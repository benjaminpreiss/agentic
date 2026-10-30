#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DEPLOY="$ROOT/.deployment"
[[ -f "$DEPLOY/flake.nix" && -f "$DEPLOY/generated/machine.nix" && -f "$DEPLOY/generated/facter.json" && -f "$DEPLOY/target.txt" ]] || {
  echo 'Missing prepared deployment configuration; refusing to apply.' >&2
  exit 1
}
TARGET="${TARGET:-$(cat "$DEPLOY/target.txt")}"; HOST="${TARGET#*@}"
[[ -n "$HOST" && "$HOST" != "$TARGET" ]] || { echo 'Expected user@host in deployment target.' >&2; exit 1; }
for file in flake.nix modules/agentic.nix; do
  [[ -f "$ROOT/$file" ]] || { echo "Missing $file" >&2; exit 1; }
  cp "$ROOT/$file" "$DEPLOY/$file"
done
# Preserve existing flake.lock and pins; do not upgrade inputs on an apply.
if [[ ! -f "$DEPLOY/flake.lock" ]]; then
  echo 'Missing .deployment/flake.lock; run the normal configuration preparation process first.' >&2
  exit 1
fi
echo 'Evaluating NixOS configuration (non-destructive)...'
nix eval --raw "path:$DEPLOY#nixosConfigurations.agentic.config.system.build.toplevel.drvPath" >/dev/null
printf 'Apply new NixOS generation to root@%s (no partition changes)? [y/N] ' "$HOST" > /dev/tty
IFS= read -r answer < /dev/tty
[[ "$answer" == y || "$answer" == Y ]] || exit 1
nix run nixpkgs#nixos-rebuild -- switch --flake "path:$DEPLOY#agentic" --target-host "root@$HOST" --build-host "root@$HOST"
echo 'Activating and verifying nono pack provisioning...'
# Ensure the systemd oneshot is executed now, not merely enabled for next boot.
ssh -o BatchMode=yes "root@$HOST" 'bash -se' <<'REMOTE'
set -euo pipefail
systemctl daemon-reload
systemctl start agentic-skills.service
systemctl restart agentic-nono-pack.service
systemctl is-active --quiet agentic-nono-pack.service
# Confirm the child profile resolves with nono under the same user/HOME.
runuser -u agentic -- env HOME=/home/agentic PATH=/run/current-system/sw/bin:/usr/bin:/bin \
  nono run --profile pi-herdr --allow-cwd --dry-run -- /run/current-system/sw/bin/true >/dev/null
printf 'nono registry pack and pi-herdr profile verified.\n'
REMOTE
echo 'Apply completed and nono sandbox provisioning verified.'
