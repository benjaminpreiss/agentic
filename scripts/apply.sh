#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DEPLOY="$ROOT/.deployment"
for f in flake.nix flake.lock generated/machine.nix generated/facter.json target.txt; do
  [[ -f "$DEPLOY/$f" ]] || { echo "Missing .deployment/$f" >&2; exit 1; }
done
TARGET="${TARGET:-$(cat "$DEPLOY/target.txt")}"; HOST="${TARGET#*@}"
[[ -n "$HOST" && "$HOST" != "$TARGET" ]] || { echo 'Expected user@host in target.txt' >&2; exit 1; }
# The Nix module reads these shell sources at evaluation time, so stage them
# alongside the module. They contain code only; credentials never enter the flake.
mkdir -p "$DEPLOY/scripts"
for f in flake.nix modules/base.nix modules/agentic.nix modules/github-mcp.nix \
  scripts/git-app-token-broker.sh scripts/git-credential-helper.sh \
  scripts/configure-git-credentials.sh; do
  [[ -f "$ROOT/$f" ]] || { echo "Missing $f" >&2; exit 1; }
  cp "$ROOT/$f" "$DEPLOY/$f"
done
# Local nono profiles are part of the flake source too.
mkdir -p "$DEPLOY/profiles"
for f in pi-herdr.json omp-agentic.json; do
  [[ -f "$ROOT/profiles/$f" ]] || { echo "Missing profiles/$f" >&2; exit 1; }
  cp "$ROOT/profiles/$f" "$DEPLOY/profiles/$f"
done
# Secrets are streamed directly over SSH, never placed beneath .deployment:
# Nix may copy the entire evaluated flake source into the world-readable store.
sync_github_app_secrets() {
  local secrets="$ROOT/secrets/github-app"
  local envfile="$secrets/app.env"
  local keyfile="$secrets/private-key.pem"
  if [[ ! -e "$envfile" && ! -e "$keyfile" ]]; then
    echo 'No local GitHub App credentials: retaining any credentials already on VPS.'
    return 0
  fi
  [[ -f "$envfile" && -f "$keyfile" && ! -L "$envfile" ]] || {
    echo 'Missing app.env or active private-key.pem in secrets/github-app/.' >&2
    return 1
  }
  # The active key may be a symlink to another PEM in this same folder.
  # Reject links outside the secrets directory, including dangling links.
  local resolved_dir resolved_key
  resolved_dir="$(cd "$secrets" && pwd -P)"
  resolved_key="$(realpath -e "$keyfile")" || return 1
  case "$resolved_key" in
    "$resolved_dir"/*) ;;
    *) echo 'private-key.pem must point to a PEM within secrets/github-app/' >&2; return 1 ;;
  esac
  local app_id installation_id
  app_id="$(sed -n 's/^GITHUB_APP_ID=//p' "$envfile")"
  installation_id="$(sed -n 's/^GITHUB_APP_INSTALLATION_ID=//p' "$envfile")"
  [[ "$app_id" =~ ^[0-9]+$ && "$installation_id" =~ ^[0-9]+$ ]] || {
    echo 'Invalid GitHub App IDs in app.env' >&2; return 1;
  }
  openssl pkey -in "$keyfile" -noout >/dev/null 2>&1 || {
    echo 'Invalid private key PEM' >&2; return 1;
  }
  echo "Uploading GitHub App credentials to root@$HOST over SSH..."
  # Archive is transmitted via the SSH pipe; no shared /tmp files and no Nix store.
  tar -h -C "$secrets" -cf - app.env private-key.pem |     ssh -o BatchMode=yes "root@$HOST" 'set -eu
      umask 077
      install -d -m 0700 -o root -g root /etc/agentic
      install -d -m 0700 -o root -g root /etc/agentic/github-app
      staging="$(mktemp -d /etc/agentic/.github-app.XXXXXXXX)"
      trap "rm -rf -- \"$staging\"" EXIT
      tar -xf - -C "$staging" --no-same-owner --no-same-permissions
      test -s "$staging/app.env"
      test -s "$staging/private-key.pem"
      install -m 0600 -o root -g root "$staging/app.env" /etc/agentic/github-app/.app.env.new
      install -m 0600 -o root -g root "$staging/private-key.pem" /etc/agentic/github-app/.private-key.pem.new
      mv -f /etc/agentic/github-app/.app.env.new /etc/agentic/github-app/app.env
      mv -f /etc/agentic/github-app/.private-key.pem.new /etc/agentic/github-app/private-key.pem
    '
  echo 'GitHub App credentials installed as root-only files.'
}
printf 'Evaluating NixOS system (no disk changes)...\n'
nix eval --raw "path:$DEPLOY#nixosConfigurations.agentic.config.system.build.toplevel.drvPath" >/dev/null
printf 'Apply NixOS changes to root@%s (no repartition)? [y/N] ' "$HOST" >/dev/tty
IFS= read -r answer </dev/tty
[[ "$answer" == y || "$answer" == Y ]] || exit 0
sync_github_app_secrets
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
runuser -u agentic -- env HOME="$home" PATH=/run/current-system/sw/bin:/usr/bin:/bin "$nono" pull nolabs-ai/omp
runuser -u agentic -- env HOME="$home" PATH=/run/current-system/sw/bin:/usr/bin:/bin "$nono" list --installed
runuser -u agentic -- env HOME="$home" PATH=/run/current-system/sw/bin:/usr/bin:/bin sh -c \
  'cd /home/agentic/work && exec nono run --profile pi-herdr --allow-cwd --dry-run -- /run/current-system/sw/bin/true' >/dev/null
runuser -u agentic -- env HOME="$home" PATH=/run/current-system/sw/bin:/usr/bin:/bin sh -c \
  'cd /home/agentic/work && exec nono run --profile omp-agentic --allow-cwd --dry-run -- /run/current-system/sw/bin/true' >/dev/null
echo 'nono packages and pi-herdr/omp-agentic profiles verified.'
REMOTE
then
  echo 'Apply completed, including nono verification.'
else
  echo 'NixOS activation succeeded, but nono setup failed. Do not rebuild again for the same failure.' >&2
  exit 2
fi
