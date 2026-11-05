#!/usr/bin/env bash
# GitHub App credentials are transferred separately, never through Nix source.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
[[ $# == 1 && $1 =~ ^root@[a-zA-Z0-9_.:-]+$ ]] || { echo 'usage: credentials.sh root@HOST' >&2; exit 2; }
secrets="$ROOT/secrets/github-app"
envfile="$secrets/app.env"; keyfile="$secrets/private-key.pem"
[[ -f "$envfile" && ! -L "$envfile" && -f "$keyfile" ]] || { echo 'Missing local GitHub App files' >&2; exit 1; }
resolved_dir=$(cd "$secrets" && pwd -P)
resolved_key=$(realpath "$keyfile")
case "$resolved_key" in "$resolved_dir"/*) ;; *) echo 'Key must resolve inside secrets/github-app' >&2; exit 1 ;; esac
[[ $(stat -c %a "$envfile") == 600 ]] || { echo 'app.env must be mode 600' >&2; exit 1; }
app_id=$(sed -n 's/^GITHUB_APP_ID=//p' "$envfile")
installation_id=$(sed -n 's/^GITHUB_APP_INSTALLATION_ID=//p' "$envfile")
[[ $app_id =~ ^[0-9]+$ && $installation_id =~ ^[0-9]+$ ]] || { echo 'Invalid GitHub App identifiers' >&2; exit 1; }
openssl pkey -in "$keyfile" -noout >/dev/null 2>&1 || { echo 'Invalid private key' >&2; exit 1; }
tar -h -C "$secrets" -cf - app.env private-key.pem | ssh -o StrictHostKeyChecking=yes "$1" 'set -eu
  umask 077
  install -d -m 0700 -o root -g root /etc/agentic/github-app
  staging="$(mktemp -d /etc/agentic/.github-app.XXXXXXXX)"
  trap "rm -rf -- \"$staging\"" EXIT
  tar -xf - -C "$staging" --no-same-owner --no-same-permissions
  test -s "$staging/app.env" && test -s "$staging/private-key.pem"
  install -m 0600 -o root -g root "$staging/app.env" /etc/agentic/github-app/.app.env.new
  install -m 0600 -o root -g root "$staging/private-key.pem" /etc/agentic/github-app/.private-key.pem.new
  mv -f /etc/agentic/github-app/.app.env.new /etc/agentic/github-app/app.env
  mv -f /etc/agentic/github-app/.private-key.pem.new /etc/agentic/github-app/private-key.pem'
echo 'Credentials transferred as root-only files; no Nix store or shared toolkit upload.'
