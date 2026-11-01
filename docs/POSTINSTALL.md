# After NixOS installation

1. Confirm you can SSH with your configured public key. On reinstallation, the server SSH host key changes; verify its new fingerprint through a trusted console before updating known_hosts.
2. Review `.deployment/generated/facter.json` and keep this report with the machine's durable configuration; ensure future rebuilds refer to the report and same flake lock.
3. Set up Pi (`@earendil-works/pi-coding-agent`), nono with `nolabs-ai/pi`, Herdr/`hc`, and Matt Pocock skills. This initial bundle does **not** configure them yet. The installed `nnpi` launcher is a guard/placeholder until those tools and the profile exist.
4. For Herdr and nono extension loading, retain `JITI_FS_CACHE=false` and keep work within `~/work`.
5. Configure the GitHub App / MCP service separately, outside the nono sandbox, with systemd credentials or agenix/sops-nix. Do not commit private keys.
6. Protect each repository's default branch with a default-branch-only GitHub ruleset; keep work branches directly pushable and test enforcement before autonomous merges.
7. Review NixOS update policy before enabling unattended rebuilds. Backups stored on the same disk are insufficient for disaster recovery.
