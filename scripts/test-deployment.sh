#!/usr/bin/env bash
# Synthetic machine: no SSH, Disko, installer or real credentials.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
bash "$ROOT/scripts/test-stage.sh"
bash "$ROOT/scripts/github/test-configure-git-credentials.sh"
[[ $(jq -r '.nodes.themoss.locked.rev' "$ROOT/flake.lock") == 05f25bf2e700deb55c59882d00e781a1e1583d07 ]]
[[ $(nix --extra-experimental-features 'nix-command flakes' eval --raw --no-write-lock-file "path:$ROOT#toolkitPath") == /nix/store/* ]]
# Git archive of the next commit must be symlink-free: this is a requirement of
# the shared staging interface, not a license to archive secrets.
if git -C "$ROOT" ls-files -s | grep -q '^120000 '; then echo 'Committed symlink prevents toolkit staging' >&2; exit 1; fi
fixture=$(mktemp -d "$ROOT/.deployment.fixture.XXXXXXXX")
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/source"
# Only reviewed public source; never include .deployment/ or secrets/.
tar -C "$ROOT" --exclude=.git --exclude=.fixture --exclude='.deployment*' --exclude=secrets -cf - \
  flake.nix flake.lock nixos deployment skills scripts github-protection | tar -xf - -C "$fixture/source"
mkdir "$fixture/source/generated"
printf '{ ... }: { agenticMachine = { hostname = "fixture"; disk = "/dev/vda"; bootMode = "bios"; sshKey = "ssh-ed25519 AAAAfixture"; networkMAC = "02:00:00:00:00:01"; }; }\n' > "$fixture/source/generated/machine.nix"
printf '{"disk":{"path":"/dev/vda"},"boot":"bios","mac":"02:00:00:00:00:01","arch":"x86_64"}\n' > "$fixture/record.json"
bash "$ROOT/scripts/deployment/pre-erase.sh" "$fixture/source" agentic "$fixture/record.json"
[[ $(nix --extra-experimental-features 'nix-command flakes' eval --json --no-write-lock-file "path:$fixture/source#nixosConfigurations.agentic.config.services.themossUpdate.enable") == true ]]
[[ $(nix --extra-experimental-features 'nix-command flakes' eval --json --no-write-lock-file "path:$fixture/source#nixosConfigurations.agentic.config.system.autoUpgrade.enable") == false ]]
[[ ! -e "$fixture/source/secrets" && ! -e "$fixture/source/.deployment" ]]
# A mismatched boot record must fail before the destructive call.
jq '.boot = "uefi"' "$fixture/record.json" > "$fixture/record-wrong.json"
if bash "$ROOT/scripts/deployment/pre-erase.sh" "$fixture/source" agentic "$fixture/record-wrong.json" >/dev/null 2>&1; then
  echo 'Pre-erase check accepted mismatched target' >&2; exit 1
fi
echo 'Agentic flake, manual-only legacy staging, selector-based poller and pre-erase checks passed.'
