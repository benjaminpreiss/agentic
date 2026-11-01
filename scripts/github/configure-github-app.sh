#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
DIR="$ROOT/secrets/github-app"
umask 077
mkdir -p "$DIR"
chmod 700 "$DIR"
read -r -p 'GitHub App ID: ' APP_ID
read -r -p 'GitHub App installation ID: ' INSTALL_ID
[[ "$APP_ID" =~ ^[0-9]+$ ]] || { echo 'App ID must be numeric' >&2; exit 1; }
[[ "$INSTALL_ID" =~ ^[0-9]+$ ]] || { echo 'Installation ID must be numeric' >&2; exit 1; }
KEY_PATH="$DIR/private-key.pem"
[[ -f "$KEY_PATH" && -s "$KEY_PATH" && -r "$KEY_PATH" ]] || {
  echo "Place your GitHub App PEM at: $KEY_PATH" >&2
  exit 1
}
# Do not permit a symlink to escape the GitHub App secrets directory.
resolved_dir="$(cd "$DIR" && pwd -P)"
resolved_key="$(realpath "$KEY_PATH")"
case "$resolved_key" in
  "$resolved_dir"/*) ;;
  *) echo "The active private-key.pem must resolve inside $DIR" >&2; exit 1 ;;
esac
grep -q -- '-----BEGIN .*PRIVATE KEY-----' "$KEY_PATH" || {
  echo "Not a valid PEM private key: $KEY_PATH" >&2
  exit 1
}
chmod 600 "$resolved_key"
printf 'GITHUB_APP_ID=%s\nGITHUB_APP_INSTALLATION_ID=%s\n' "$APP_ID" "$INSTALL_ID" > "$DIR/app.env"
chmod 600 "$DIR/app.env"
echo "Saved local GitHub App credentials to $DIR (ignored by Git)."
