#!/usr/bin/env bash
# Build the .deployment/ Nix flake source for BOTH prepare.sh and apply.sh.
# The source layout here matches paths referenced by nixos/modules/*.nix:
# modules/, scripts/, profiles/, github-protection/, skills/ and flake.nix.
# Only these reviewed, credential-free inputs are copied; generated machine
# records and flake.lock stay in the destination, secrets/ never enters it.
# Run through the install/update workflows, not as an operator command.
# Bash 3.2 compatible; never copy the whole repository.
set -euo pipefail
[[ $# == 1 ]] || { echo 'Usage: bash scripts/stage.sh DEPLOY_DIR' >&2; exit 2; }
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DEST="$1"
[[ -d "$DEST" && ! -L "$DEST" ]] || { echo 'Deployment directory must exist and must not be a symlink' >&2; exit 1; }
DEST="$(cd "$DEST" && pwd -P)"
case "$DEST/" in "$ROOT/"*) ;; *) echo 'Deployment must be inside this checkout' >&2; exit 1 ;; esac
# Restrict links to the one intentionally linked tree. Do not follow links while
# copying: Nix must see the same source tree that was validated here.
for dir in "$ROOT/nixos" "$ROOT/github-protection" "$ROOT/scripts/runtime" "$ROOT/scripts/github" "$ROOT/skills/available"; do
  [[ -d "$dir" && ! -L "$dir" ]] || { echo "Missing or linked source: $dir" >&2; exit 1; }
  if find "$dir" -type l -print | grep -q .; then
    echo "Unexpected symlink in $dir" >&2; exit 1
  fi
done
command -v nix >/dev/null && command -v jq >/dev/null || { echo 'Nix and jq required for skill selection' >&2; exit 1; }
SELECTION="$(nix --extra-experimental-features 'nix-command flakes' eval --json --file "$ROOT/skills/enabled.nix")"
# The legacy deployment flake still needs enabled/ links until an existing host
# has been explicitly migrated. Reconstruct only validated, in-tree links.
while IFS=$'\t' read -r name relative; do
  [[ $name =~ ^[a-zA-Z0-9_-]+$ && $relative =~ ^[a-zA-Z0-9_/-]+$ && $relative != /* && $relative != *..* ]] || {
    echo "Invalid selected skill: $name $relative" >&2; exit 1;
  }
  [[ -f "$ROOT/skills/available/$relative/SKILL.md" ]] || { echo "Missing selected skill: $relative" >&2; exit 1; }
done < <(jq -r 'to_entries[] | [.key,.value] | @tsv' <<<"$SELECTION")
# Build all managed sources before touching the existing deployment. Preserve
# generated/, extra-files/, flake.lock and the machine's target/selection files.
umask 077
TMP="$(mktemp -d "$DEST/.source.XXXXXXXX")"
trap 'rm -rf "$TMP"' EXIT
cp "$ROOT/nixos/flake.nix" "$TMP/flake.nix"
cp -R "$ROOT/nixos/modules" "$TMP/modules"
cp -R "$ROOT/nixos/profiles" "$TMP/profiles"
mkdir -p "$TMP/scripts" "$TMP/skills" "$TMP/github-protection"
cp -R "$ROOT/scripts/runtime/." "$TMP/scripts/"
cp "$ROOT/scripts/github/configure-git-credentials.sh" "$TMP/scripts/"
for f in check.sh github-api.sh ci.sh policy.jq rulesets.jq; do
  cp "$ROOT/github-protection/$f" "$TMP/github-protection/$f"
done
cp -R "$ROOT/skills/available" "$TMP/skills/available"
mkdir "$TMP/skills/enabled"
while IFS=$'\t' read -r name relative; do
  ln -s "../available/$relative" "$TMP/skills/enabled/$name"
  [[ -f "$TMP/skills/enabled/$name/SKILL.md" ]] || { echo "Staged skill invalid: $name" >&2; exit 1; }
done < <(jq -r 'to_entries[] | [.key,.value] | @tsv' <<<"$SELECTION")
# Remove old managed trees, including stale modules/scripts/skills, while
# leaving all machine-specific records untouched. A failed copy never reaches
# this point.
for entry in flake.nix modules profiles scripts github-protection skills; do
  rm -rf "$DEST/$entry"
  mv "$TMP/$entry" "$DEST/$entry"
done
