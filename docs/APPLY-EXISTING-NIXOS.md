# Apply Agentic NixOS shell and dashboard fixes

These changes are for an **already installed, SSH-reachable NixOS machine**. Do **not** run `scripts/deploy.sh --install` again. The Disko installation command erases the disk.

## Changed files

- Replace `modules/agentic.nix`: Ghostty terminfo, initialize missing `~/.zshrc`, Starship prompt, welcome screen, firewall allowances, existing backup timer.
- Add `scripts/apply.sh`: copy updated modules to `.deployment`, evaluate final configuration, and run a remote `nixos-rebuild switch` (no repartitioning).
- Add this document.

The remaining files from your currently working deployment are unchanged. In particular, keep your working MAC-address network configuration, BIOS boot setup, recovery account and machine-specific `.deployment` configuration.

## Apply from your Mac

1. Replace/add the files in your local `agentic-main` directory. There is no need to commit them before applying.
2. Ensure `.deployment/generated/facter.json`, `.deployment/generated/machine.nix` and `.deployment/flake.nix` exist from your successful install.
3. Test that SSH works: `ssh root@YOUR_HOST 'cat /etc/os-release'`.
4. Run `bash scripts/apply.sh` from the repository directory.
5. Reconnect using `ssh agentic@YOUR_HOST`. The Zsh first-time wizard should not appear, and the welcome banner should describe the firewall allow rules, not listening sockets.

The helper updates your local `.deployment/modules/{agentic,base}.nix` and uses remote NixOS evaluation/build/activation. The current OS may be kept on NixOS 26.05; moving to a stable release is a separate, deliberate upgrade, not part of this repair.

If the rebuild fails, the old NixOS generation remains available. Do not run the disk installer to fix a rebuild problem.

## What this does not install

The current baseline does **not** yet install Pi, nono, Herdr, Herdr Core, Matt Pocock skills or GitHub MCP. `nnpi` is a prepared launcher and reports a missing executable until those components are provisioned. Do not assume the remaining Ubuntu provisioning has automatically migrated.

OS upgrade automation is also not enabled here: configuration is currently installed from a local generated flake. Backups still run daily, but are **local to the server** and not a substitute for off-server backups.

## Additional hardening notes

`programs.zsh.interactiveShellInit` already loads the dashboard even in a non-login interactive shell. The activation script only creates `~/.zshrc` if missing; it does not overwrite a user's existing file. The `ghostty.terminfo` package supplies `xterm-ghostty` capabilities.

Displayed firewall values are global NixOS allow-list settings; there may be other per-interface or service-specific allowances. Inspect `sudo nft list ruleset` on the target for effective runtime rules.
