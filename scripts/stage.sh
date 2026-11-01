#!/usr/bin/env bash
# Shared, credential-free flake source staging for install and update.
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
[[ -d "$ROOT/skills/enabled" && ! -L "$ROOT/skills/enabled" ]] || { echo 'Missing skills/enabled' >&2; exit 1; }
for link in "$ROOT"/skills/enabled/*; do
  [[ -e "$link" || -L "$link" ]] || continue
  [[ -L "$link" ]] || { echo "Enabled skill must be a symlink: $link" >&2; exit 1; }
  name="${link##*/}"; target="$(readlink "$link")"
  case "$name" in *[!a-zA-Z0-9_-]*|'') echo "Invalid skill name: $name" >&2; exit 1 ;; esac
  # No absolute paths, traversal, or chains. Only reviewed skill directories.
  case "$target" in ../available/*) ;; *) echo "Escaping enabled skill: $link -> $target" >&2; exit 1 ;; esac
  case "$target/" in *'/../'*|*'/./'*|*'//'*) echo "Invalid skill target: $link -> $target" >&2; exit 1 ;; esac
  [[ -d "$link" && -f "$link/SKILL.md" && ! -L "$link/SKILL.md" ]] || {
    echo "Broken skill or missing SKILL.md: $link -> $target" >&2; exit 1;
  }
done
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
cp -R "$ROOT/skills/enabled" "$TMP/skills/enabled"
# Validate the copied links as well (cp -R must preserve symlinks).
for link in "$TMP"/skills/enabled/*; do
  [[ -e "$link" || -L "$link" ]] || continue
  [[ -L "$link" && -f "$link/SKILL.md" ]] || { echo "Staged skill link invalid: $link" >&2; exit 1; }
done
# Remove old managed trees, including stale modules/scripts/skills, while
# leaving all machine-specific records untouched. A failed copy never reaches
# this point.
for entry in flake.nix modules profiles scripts github-protection skills; do
  rm -rf "$DEST/$entry"
  mv "$TMP/$entry" "$DEST/$entry"
done
