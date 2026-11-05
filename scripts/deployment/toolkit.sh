#!/usr/bin/env bash
# Public moss operator CLI, at the immutable revision in agentic/flake.lock.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
[[ -f "$ROOT/flake.lock" ]] || { echo 'Missing committed flake.lock' >&2; exit 1; }
toolkit=$(nix --extra-experimental-features 'nix-command flakes' eval --raw --no-write-lock-file "path:$ROOT#toolkitPath")
[[ -x "$toolkit/packages/cli/bin/moss" ]] || { echo 'Pinned moss CLI not found' >&2; exit 1; }
cd "$ROOT"
exec "$toolkit/packages/cli/bin/moss" "$@"
