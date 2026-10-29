#!/usr/bin/env bash
# Generate a salted SHA-512 password hash using a TTY prompt; never store plaintext.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DEPLOY="$ROOT/.deployment"
[[ -d "$DEPLOY" ]] || { echo 'Run prepare.sh first' >&2; exit 1; }
command -v nix >/dev/null || { echo 'Nix is required to run mkpasswd' >&2; exit 1; }
[[ -r /dev/tty ]] || { echo 'Interactive terminal required' >&2; exit 1; }
DEST="$DEPLOY/extra-files/etc/agentic/recovery-password-hash"
umask 077
mkdir -p "$(dirname "$DEST")"
# mkpasswd reads the password interactively from the terminal.
# Redirect output only, never save or log the plaintext password.
TMP="$DEST.partial"
trap 'rm -f "$TMP"' EXIT
nix --extra-experimental-features 'nix-command flakes' shell nixpkgs#mkpasswd --command bash -c 'command -v mkpasswd >/dev/null || { echo "mkpasswd is missing from the Nix environment" >&2; exit 1; }; exec mkpasswd -m sha-512' < /dev/tty > "$TMP"
[[ "$(wc -l < "$TMP" | tr -d ' ')" == 1 ]] || { echo 'Invalid hash output' >&2; exit 1; }
grep -q '^\$6\$' "$TMP" || { echo 'Expected a SHA-512 crypt hash' >&2; exit 1; }
chmod 0600 "$TMP"
mv "$TMP" "$DEST"
trap - EXIT
printf 'Recovery password hash saved outside Git: %s\n' "$DEST"
