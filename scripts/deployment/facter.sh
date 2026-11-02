#!/usr/bin/env bash
# Optional shared-installer hook: run a pinned facter on a rescue target with Nix.
set -euo pipefail
[[ $# == 2 ]] || { echo 'usage: facter.sh TARGET OUTPUT_JSON' >&2; exit 2; }
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
rev=$(jq -er '.nodes.nixpkgs.locked.rev | select(test("^[0-9a-f]{40}$"))' "$ROOT/flake.lock")
# The target must have Nix and flakes enabled; never accept a new SSH host key.
ssh -o StrictHostKeyChecking=yes "$1" "nix --extra-experimental-features 'nix-command flakes' run github:NixOS/nixpkgs/$rev#nixos-facter -- -o /dev/stdout" > "$2"
jq -e 'type == "object"' "$2" >/dev/null
