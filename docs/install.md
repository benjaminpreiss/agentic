# Install agentic on a new machine

> ⚠️ **Fresh install erases a whole disk.** For an existing agentic host, use the [update guide](update.md). Merging this PR does not change a server.

The operator chooses the machine and disk. The pinned themoss.net toolkit discovers its hardware, builds agentic, checks the target again and demands a **typed disk confirmation**. It is the only path that runs Disko.

## 1. Prepare on your deployment computer

- Back up the target **off-server**; verify its recovery console and the rescue SSH host fingerprint *through the provider console*.
- Review and push the exact agentic commit you intend to install. Its root `flake.lock` pins the toolkit and Nix dependencies.
- Use Nix with flakes, SSH and jq. On macOS, enter the toolkit's pinned GNU-tool shell and configure a **Linux Nix builder** (or use a Linux VM):

  ```bash
  toolkit=$(nix eval --raw --no-write-lock-file "path:$PWD#toolkitPath")
  nix develop --no-write-lock-file "path:$toolkit#operator"
  bash scripts/test-deployment.sh
  ```

  The shell is tested on Linux; native macOS use has **not** been validated on a live server. Keep keys, password hashes and credentials outside Git and the Nix store.

## 2. Discover and review the target

```bash
bash scripts/deployment/prepare.sh
bash scripts/install/recovery-password.sh
bash scripts/deployment/toolkit.sh preflight .deployment/record.json
```

`prepare.sh` shows the rescue host's whole disks and asks **you** to type the `/dev/…` disk to erase. *It never chooses one.* It detects architecture, boot mode, default-route NIC and MAC. DHCP is suggested only when the rescue host reports lease evidence; otherwise choose DHCP or supply static IPv4/CIDR, gateway and DNS explicitly. The script generates private `.deployment/record.json` and `generated/machine.nix` and refuses to overwrite an existing `.deployment/`.

Review the disk, boot and network settings **against the provider console**. The recovery-password command saves a hash for the console account in `.deployment/extra-files/`, never in the flake. Toolkit preflight re-probes the target without formatting anything.

<details>
<summary>Non-interactive preparation</summary>

If you already know the target settings, pass them explicitly:

```bash
bash scripts/deployment/prepare.sh root@HOST /dev/WHOLE_DISK HOSTNAME ~/.ssh/id_ed25519.pub dhcp
# Static: replace dhcp with static IPv4/CIDR GATEWAY COMMA_SEPARATED_DNS
```

Both paths call the same shared discovery and later require typed erase confirmation.
</details>

## 3. Install the reviewed commit

**Stop unless the off-host backup and console recovery work.** From a clean checkout at the pushed branch tip:

```bash
bash scripts/deployment/install.sh
```

The short adapter supplies agentic's paths and checks to the pinned toolkit. The toolkit verifies the pushed commit, generates a private hardware report using `nixos-facter` *if one does not already exist*, builds the NixOS derivation, evaluates agentic's effective disk/boot/network/SSH choices, re-probes, then prompts for `ERASE /dev/WHOLE_DISK`. The rescue host needs Nix with flakes for facter; if it lacks Nix, **stop** and prepare a reviewed report first. The recovery hash travels separately via `--extra-files`. Neither it nor GitHub App keys enter the flake.

**If install succeeds but receipt creation fails, do not rerun the installer.** Inspect the installed revision via console and keep the original private records.

## 4. Verify the new SSH key, then bootstrap

The installed system has a *different* SSH host key. Verify it via the provider console before updating `known_hosts`:

```bash
bash scripts/deployment/toolkit.sh bootstrap \
  .deployment/install-receipt.json "$PWD" .deployment/generated \
  /var/lib/agentic/source /var/lib/agentic/machine /var/lib/agentic/deployment
```

Bootstrap checks the receipt against the original machine files, creates a root-owned checkout at the installed commit and pins the host to **`commit:INSTALLED_SHA`**. The poll timer is present but does nothing until an operator explicitly selects a branch. Interrupted bootstrap may be retried with the *same* receipt; never reinstall to repair it.

If configured, transfer GitHub App credentials **separately** with `bash scripts/deployment/credentials.sh root@HOST`. Verify SSH, networking, recovery-console login, `agentic-firstboot-check`, and agentic's services. Back up `.deployment/` off-host. See [tracking and recovery](update.md).
