#!/usr/bin/env bash
# Copy only the audit sources referenced by modules/github-mcp.nix into a
# deployment flake. Never stage App credentials or the local test fixtures.
set -euo pipefail
[[ $# == 1 && -d "$1" ]] || { echo 'Usage: bash scripts/stage-github-protection.sh DEPLOY_DIR' >&2; exit 2; }
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
mkdir -p "$1/github-protection"
for f in check.sh github-api.sh ci.sh policy.jq rulesets.jq; do
  [[ -f "$ROOT/github-protection/$f" ]] || { echo "Missing github-protection/$f" >&2; exit 1; }
  cp "$ROOT/github-protection/$f" "$1/github-protection/$f"
done
