#!/usr/bin/env bash
# Preserve the old host's private state while testing legacy staging from the
# same manifest used by the new, symlink-free root flake.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
tmp="$(mktemp -d "$ROOT/.deployment.stage.test.XXXXXXXX")"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/repo"/{nixos/modules,nixos/profiles,github-protection,scripts/runtime,scripts/github,skills/available/demo,.deployment/generated,.deployment/extra-files,secrets}
cp "$ROOT/scripts/stage.sh" "$tmp/repo/scripts/stage.sh"
printf '{}\n' > "$tmp/repo/nixos/flake.nix"
printf '{ demo = "demo"; }\n' > "$tmp/repo/skills/enabled.nix"
printf 'skill\n' > "$tmp/repo/skills/available/demo/SKILL.md"
printf 'module\n' > "$tmp/repo/nixos/modules/demo.nix"
printf 'old lock\n' > "$tmp/repo/.deployment/flake.lock"
printf 'private machine\n' > "$tmp/repo/.deployment/generated/machine.nix"
printf 'private report\n' > "$tmp/repo/.deployment/generated/facter.json"
printf 'recovery hash\n' > "$tmp/repo/.deployment/extra-files/hash"
printf 'secret\n' > "$tmp/repo/secrets/private-key"
for f in check.sh github-api.sh ci.sh policy.jq rulesets.jq; do printf 'fixture\n' > "$tmp/repo/github-protection/$f"; done
printf 'fixture\n' > "$tmp/repo/scripts/github/configure-git-credentials.sh"
bash "$tmp/repo/scripts/stage.sh" "$tmp/repo/.deployment"
[[ -f "$tmp/repo/.deployment/skills/enabled/demo/SKILL.md" ]]
[[ $(<"$tmp/repo/.deployment/flake.lock") == 'old lock' ]]
[[ $(<"$tmp/repo/.deployment/generated/machine.nix") == 'private machine' ]]
[[ -f "$tmp/repo/.deployment/generated/facter.json" && -f "$tmp/repo/.deployment/extra-files/hash" ]]
[[ ! -e "$tmp/repo/.deployment/secrets" ]]
printf '{ demo = "../../secrets"; }\n' > "$tmp/repo/skills/enabled.nix"
if bash "$tmp/repo/scripts/stage.sh" "$tmp/repo/.deployment" 2>/dev/null; then echo 'Accepted escaping skill!' >&2; exit 1; fi
[[ -f "$tmp/repo/.deployment/skills/enabled/demo/SKILL.md" ]]
printf '{ demo = "missing"; }\n' > "$tmp/repo/skills/enabled.nix"
if bash "$tmp/repo/scripts/stage.sh" "$tmp/repo/.deployment" 2>/dev/null; then echo 'Accepted missing skill!' >&2; exit 1; fi
echo 'Legacy staging preserves private state and validates selected skills.'
