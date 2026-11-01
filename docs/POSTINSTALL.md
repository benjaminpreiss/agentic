# After NixOS installation

1. Confirm you can SSH as `agentic` with your configured public key. On reinstallation, the server SSH host key changes; verify its new fingerprint through a trusted console before updating `known_hosts`.
2. Test logging in as `recovery` through the provider console. Keep this path available until remote access is stable.
3. Keep `.deployment/generated/facter.json`, `.deployment/generated/machine.nix`, and `.deployment/flake.lock` with your private deployment records; future updates use these files.
4. Check `journalctl -u agentic-firstboot-check -b --no-pager` and verify networking and SSH. See the first-boot checks in [the README](../README.md#5-verify-the-first-boot).
5. From `~/work`, try `pi` and `omp`. The NixOS modules declare the launchers, nono, Herdr, and skills; the nono registry packs are prepared by `scripts/apply.sh`, not the fresh installer. If a launcher reports a missing pack after installation, follow the non-destructive [update instructions](APPLY-EXISTING-NIXOS.md). See [SANDBOXED-AGENTS.md](SANDBOXED-AGENTS.md) for sandbox details.
6. If you need GitHub App-backed MCP and Git HTTPS credentials, follow [the GitHub setup guide](../AGENTIC_GITHUB_SETUP.md). Keep the private key outside `.deployment/` and the Nix store.
7. Protect important GitHub branches before autonomous pushes or merges. Backups stored on the server are not a substitute for off-server backups; unattended NixOS system upgrades are disabled.
