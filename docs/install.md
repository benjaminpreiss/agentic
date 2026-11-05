# Install agentic on a new machine

> ⚠️ **A fresh installation erases a whole disk.** Existing hosts use the [update guide](update.md). Merging this PR changes no server.

The **pinned `moss` CLI** now owns the operator lifecycle: `init → machine plan → machine apply → machine bootstrap`. Agentic supplies only its host/network choices, private recovery files and evaluated pre-erase checks. A *plan* proposes a disk; **only `apply` can erase it**, after another probe and typed `ERASE /dev/…` consent.

## 1. Before connecting

- Back up the target **off-server**. Check the rescue console and independently verify its SSH host fingerprint through the provider console.
- Review and push the exact agentic commit to deploy. The committed root `flake.lock` pins Nixpkgs and themoss.net.
- On the operator computer, use Nix with flakes, SSH, jq and the toolkit's pinned shell (GNU tools on macOS):

  ```bash
  toolkit=$(nix eval --raw --no-write-lock-file "path:$PWD#toolkitPath")
  nix develop --no-write-lock-file "path:$toolkit#operator"
  bash scripts/test-deployment.sh
  ```

  A Mac also needs a **Linux Nix builder** or a Linux VM. This shell is CI-tested on Linux; a real macOS install has not been validated. Credentials never belong in Nix source or the store.

## 2. Prepare agentic's machine configuration

```bash
bash scripts/deployment/prepare.sh
bash scripts/install/recovery-password.sh
```

`prepare.sh` asks for the verified SSH target, shows whole disks and asks you to **name the disk**; it does not choose one. It reads architecture, boot mode, NIC/MAC and suggests DHCP only with positive lease evidence. You supply the hostname, SSH public key and any static IP, gateway and DNS. It creates private, ignored `.deployment/generated/machine.nix` and `.moss/root@HOST/machine.json`, and calls the pinned `moss init` for operator-local storage.

Review both files against the provider console. The recovery-password command places a console password *hash* under `.deployment/extra-files/`, not in the flake. Neither command formats a disk.

<details>
<summary>Already know the settings?</summary>

Pass them explicitly instead of using the prompts:

```bash
bash scripts/deployment/prepare.sh root@HOST /dev/WHOLE_DISK HOSTNAME ~/.ssh/id_ed25519.pub dhcp
# For static networking: replace dhcp with static IPv4/CIDR GATEWAY COMMA_SEPARATED_DNS
```
</details>

## 3. Make and review a plan—still no disk action

```bash
bash scripts/deployment/toolkit.sh machine plan root@HOST
```

The pinned CLI reads the private `.moss/root@HOST/machine.json`. It probes the target and disk identity again, checks the exact pushed branch tip, generates the optional private `facter.json`, builds NixOS and runs agentic's **effective** disk, boot, network and SSH checks. Review its new mode-0600 plan under `.moss/root@HOST/plans/`, especially the disk, target, branch and hardware. The `latest` symlink points to the last published plan; neither it nor a plan grants erase permission.

The facter hook needs Nix with flakes on the rescue host. If it is unavailable, **stop** and arrange a reviewed report before planning. A failed report/check must not be bypassed to install.

## 4. Apply only the reviewed plan

**Stop unless off-host backups and console recovery work.** Then:

```bash
bash scripts/deployment/toolkit.sh machine apply --target root@HOST
```

`apply` repeats the build, consumer checks, target probe and pushed-tip check. If anything changed, **stop and make a new plan**. Only after these checks does it demand `ERASE /dev/WHOLE_DISK` and invoke `nixos-anywhere`/Disko. The recovery hash travels via separate `--extra-files`, never via Nix source.

If installation succeeds but the receipt is missing, **do not rerun the installer**. Inspect the installed revision via the console. Back up the receipt and original machine files off-host.

## 5. Verify the *new* host key and bootstrap

Check the installed host's new SSH fingerprint through the provider console before updating `known_hosts`:

```bash
bash scripts/deployment/toolkit.sh machine bootstrap "$PWD/.moss/root@HOST/install-receipt.json"
```

Bootstrap verifies the receipt and original private inputs, creates a root-owned checkout at the installed commit and pins the host to **`commit:INSTALLED_SHA`**. The timer is present but performs no update until an operator explicitly selects a branch. If interrupted, retry bootstrap with the *same* receipt; never reinstall as a repair.

If configured, upload GitHub App credentials **separately** with `bash scripts/deployment/credentials.sh root@HOST`. Verify network, SSH, console recovery, `agentic-firstboot-check` and agentic services. See [updates and recovery](update.md).
