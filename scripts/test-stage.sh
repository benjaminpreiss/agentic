#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
TMP="$(mktemp -d "$ROOT/.stage-test.XXXXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP"/{nixos/modules,nixos/profiles,github-protection,scripts/runtime,scripts/github,skills/available/demo,skills/enabled,.deployment/generated,.deployment/extra-files,secrets/github-app}
cp "$ROOT/scripts/stage.sh" "$TMP/scripts/stage.sh"
printf '{}\n' > "$TMP/nixos/flake.nix"
printf 'old\n' > "$TMP/.deployment/flake.lock"
printf 'machine\n' > "$TMP/.deployment/generated/machine.nix"
printf 'report\n' > "$TMP/.deployment/generated/facter.json"
printf 'hash\n' > "$TMP/.deployment/extra-files/recovery-password-hash"
printf 'PRIVATE KEY\n' > "$TMP/secrets/github-app/private-key.pem"
printf 'skill\n' > "$TMP/skills/available/demo/SKILL.md"
ln -s ../available/demo "$TMP/skills/enabled/demo"
for f in check.sh github-api.sh ci.sh policy.jq rulesets.jq; do touch "$TMP/github-protection/$f"; done
touch "$TMP/scripts/github/configure-git-credentials.sh"
printf 'module\n' > "$TMP/nixos/modules/new.nix"
printf 'runtime\n' > "$TMP/scripts/runtime/new.sh"
bash "$TMP/scripts/stage.sh" "$TMP/.deployment"
[[ -f "$TMP/.deployment/modules/new.nix" && -f "$TMP/.deployment/scripts/new.sh" ]]
[[ -f "$TMP/.deployment/skills/enabled/demo/SKILL.md" ]]
[[ -f "$TMP/.deployment/generated/facter.json" && -f "$TMP/.deployment/generated/machine.nix" ]]
[[ -f "$TMP/.deployment/flake.lock" && -f "$TMP/.deployment/extra-files/recovery-password-hash" ]]
[[ ! -e "$TMP/.deployment/secrets" ]]
# Both workflows call exactly this same staging operation.
grep -Fq 'scripts/stage.sh' "$ROOT/scripts/install/prepare.sh"
grep -Fq 'scripts/stage.sh' "$ROOT/scripts/update/apply.sh"
rm "$TMP/skills/enabled/demo"
bash "$TMP/scripts/stage.sh" "$TMP/.deployment"
[[ ! -e "$TMP/.deployment/skills/enabled/demo" ]]
ln -s ../../secrets/github-app "$TMP/skills/enabled/escape"
if bash "$TMP/scripts/stage.sh" "$TMP/.deployment" 2>/dev/null; then echo 'Accepted escaping skill!' >&2; exit 1; fi
[[ -f "$TMP/.deployment/generated/machine.nix" ]]
rm "$TMP/skills/enabled/escape"
ln -s ../available/missing "$TMP/skills/enabled/broken"
if bash "$TMP/scripts/stage.sh" "$TMP/.deployment" 2>/dev/null; then echo 'Accepted broken skill!' >&2; exit 1; fi
# Git ignore protects local credentials even when someone stages all paths.
git -C "$ROOT" check-ignore -q secrets/github-app/private-key.pem
[[ ! -e "$TMP/.deployment/secrets" ]]
echo 'Shared staging, skill selection and credential exclusion: PASS'
