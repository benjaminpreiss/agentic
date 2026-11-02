#!/usr/bin/env bash
# Invoke only the toolkit revision locked by agentic's committed flake.lock.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
[[ -f "$ROOT/flake.lock" ]] || { echo 'Missing committed flake.lock' >&2; exit 1; }
toolkit=$(nix --extra-experimental-features 'nix-command flakes' eval --raw --no-write-lock-file "path:$ROOT#toolkitPath")
[[ -f "$toolkit/toolkit/deploy.sh" ]] || { echo 'Pinned toolkit not found' >&2; exit 1; }
exec bash "$toolkit/toolkit/deploy.sh" "$@"
