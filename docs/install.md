# Install a new agentic NixOS host

> **`install` destroys the selected whole disk.** Do not run these steps on an existing host. [Update and migration](update.md) never run Disko. Test on a disposable VM first; CI does not perform a real install.

## Before starting

- Review and push the exact agentic commit to install. Its root `flake.lock` pins Nixpkgs and the themoss.net toolkit. Verify the rescue host's SSH fingerprint through the provider console before connecting.
- Back up all target data **off-server** and confirm console recovery. The operator machine needs Nix with flakes, SSH, jq, a public SSH key and a Linux Nix builder. The rescue host needs root SSH; the optional facter generator also requires Nix with flakes on the rescue host.
- From this checkout, enter the toolkit's pinned operator shell (GNU tools on macOS):

  ```bash
  toolkit=$(nix eval --raw --no-write-lock-file "path:$PWD#toolkitPath")
  nix develop --no-write-lock-file "path:$toolkit#operator"
  bash scripts/test-deployment.sh
  ```

  Mac operation has not been validated on a live server. Use a Linux VM with Nix if you cannot configure a Linux builder. Never put passwords, hashes, keys or App credentials in the flake source.

## Prepare machine facts

```bash
bash scripts/deployment/prepare.sh root@HOST /dev/WHOLE_DISK HOSTNAME ~/.ssh/id_ed25519.pub dhcp
# Or use: static IPv4/CIDR GATEWAY COMMA_SEPARATED_DNS
bash scripts/install/recovery-password.sh
bash scripts/deployment/toolkit.sh preflight .deployment/record.json
```

`prepare.sh` calls the pinned toolkit to discover architecture, boot, NIC/MAC and the *selected whole disk*; it generates agentic's private `.deployment/generated/machine.nix`. It refuses an existing `.deployment/`. Review both that file and the mode-0600 `record.json` against the provider console. Preflight re-probes; it does not erase. Keep `.deployment/` private and back it up off-host.

## Install exactly the pushed branch tip

Only after backups, console access and target facts are verified:

```bash
rev=$(git rev-parse HEAD)
branch=$(git branch --show-current)
bash scripts/deployment/toolkit.sh install \
  .deployment/record.json "$PWD" "$rev" .deployment/generated agentic "$branch" \
  .deployment/install-receipt.json \
  "$PWD/scripts/deployment/facter.sh" .deployment/extra-files \
  "$PWD/scripts/deployment/pre-erase.sh"
```

The shared toolkit requires a clean checkout and the exact pushed branch head; builds the NixOS system; runs agentic's evaluated disk/boot/network/SSH check; re-probes; then requires `ERASE /dev/WHOLE_DISK`. **Only this command runs `nixos-anywhere`/Disko.** The optional facter hook runs a Nixpkgs-revision-pinned facter on the rescue host and saves `facter.json`; if rescue Nix is unavailable, stop and arrange a reviewed report before install rather than bypassing the check. The recovery hash is sent separately via `--extra-files`, not through the Nix store.

If installation succeeds but receipt creation fails, **do not reinstall to repair it**. Verify the actual installed revision through the console. Save the receipt off-host.

## Bootstrap after first boot

Verify the *new* SSH host fingerprint through the provider console before reconnecting:

```bash
bash scripts/deployment/toolkit.sh bootstrap \
  .deployment/install-receipt.json "$PWD" .deployment/generated \
  /var/lib/agentic/source /var/lib/agentic/machine /var/lib/agentic/deployment
```

The toolkit refuses mismatched private facts and initializes the exact installed revision with a **commit pin**. The timer is present but does nothing until a reviewed transition selects a branch. If bootstrap is interrupted, retry with the same receipt, not the installer. Transfer GitHub App credentials separately if configured:

```bash
bash scripts/deployment/credentials.sh root@HOST
```

Verify SSH, network, recovery-console login, `agentic-firstboot-check`, the poll timer and agentic services. See [updates and recovery](update.md). No server changes merely by merging this PR.
