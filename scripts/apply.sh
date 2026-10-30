#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DEPLOY="$ROOT/.deployment"
for f in flake.nix flake.lock generated/machine.nix generated/facter.json target.txt; do
  [[ -f "$DEPLOY/$f" ]] || { echo "Missing .deployment/$f" >&2; exit 1; }
done
TARGET="${TARGET:-$(cat "$DEPLOY/target.txt")}"; HOST="${TARGET#*@}"
[[ -n "$HOST" && "$HOST" != "$TARGET" ]] || { echo 'Expected user@host in target.txt' >&2; exit 1; }
for f in flake.nix modules/base.nix modules/agentic.nix; do
  [[ -f "$ROOT/$f" ]] || { echo "Missing $f" >&2; exit 1; }
  cp "$ROOT/$f" "$DEPLOY/$f"
done
printf 'Evaluating NixOS system (no disk changes)...\n'
nix eval --raw "path:$DEPLOY#nixosConfigurations.agentic.config.system.build.toplevel.drvPath" >/dev/null
printf 'Apply NixOS changes to root@%s (no repartition)? [y/N] ' "$HOST" >/dev/tty
IFS= read -r answer </dev/tty
[[ "$answer" == y || "$answer" == Y ]] || exit 0
nix run nixpkgs#nixos-rebuild -- switch --flake "path:$DEPLOY#agentic" \
  --target-host "root@$HOST" --build-host "root@$HOST"
echo 'NixOS activated. Preparing and verifying nono user-state...'
if ssh -o BatchMode=yes "root@$HOST" 'bash -se' <<'REMOTE'
set -euo pipefail
home=/home/agentic
nono=/run/current-system/sw/bin/nono
# Explicitly correct the two directories proven root-owned by strace.
install -d -o agentic -g users -m 0755 "$home/.pi" "$home/.pi/agent" "$home/.pi/agent/skills"
install -d -o agentic -g users -m 0755 "$home/.config" "$home/.config/nono"
install -d -o agentic -g users -m 0700 "$home/.config/nono/profiles" "$home/.config/nono/packages" "$home/.config/nono/profile-drafts"
# No recursive chown: preserve unrelated user files.
# Repair only the known interrupted-package marker, only if pack isn't registered.
installed="$(runuser -u agentic -- env HOME="$home" "$nono" list --installed)"
if ! printf '%s\n' "$installed" | grep -Fq 'nolabs-ai/pi'; then
  marker="$home/.config/nono/profile-drafts/.nono-pi-pack-marker"
  if [[ -f "$marker" && ! -L "$marker" ]]; then
    backup_dir=/var/lib/agentic/nono-migrations
    install -d -o root -g root -m 0700 "$backup_dir"
    backup="$(mktemp "$backup_dir/nono-pi-pack-marker.XXXXXXXX")"
    cp -p -- "$marker" "$backup"
    rm -- "$marker"
    echo "Backed up the known unmanaged nono marker to $backup"
  fi
fi
# The pull is intentionally performed under the actual agent identity.
runuser -u agentic -- env HOME="$home" PATH=/run/current-system/sw/bin:/usr/bin:/bin "$nono" pull nolabs-ai/pi
runuser -u agentic -- env HOME="$home" PATH=/run/current-system/sw/bin:/usr/bin:/bin "$nono" list --installed
runuser -u agentic -- env HOME="$home" PATH=/run/current-system/sw/bin:/usr/bin:/bin sh -c \
  'cd /home/agentic/work && exec nono run --profile pi-herdr --allow-cwd --dry-run -- /run/current-system/sw/bin/true' >/dev/null
echo 'nono package and pi-herdr profile verified.'
REMOTE
then
  echo 'Apply completed, including nono verification.'
else
  echo 'NixOS activation succeeded, but nono setup failed. Do not rebuild again for the same failure.' >&2
  exit 2
fi
