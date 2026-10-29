# Postinstallation integration plan

The base install intentionally focuses on bootability, SSH access, and safe storage layout. These integrations remain to be implemented, tested, and made declarative:

1. Package `@earendil-works/pi-coding-agent` reproducibly for NixOS (or use a controlled user-level npm install as an interim approach). The `nnpi` launcher sets `JITI_FS_CACHE=false`.
2. Package nono and install its `nolabs-ai/pi` bundle. Add a minimal `pi-herdr` profile inheriting the upstream pack, granting `~/work` read/write and the global skills path read-only (subject to inherited Pi-state permissions). Validate nono's current CLI against the installed version before enabling it.
3. Install Herdr and Herdr Core (`hc`) from verified release artifacts, then `herdr integration install pi` as `agentic`. Do not assume that `herdr` and `hc` are the same executable.
4. Install Matt Pocock's skills in `~/.pi/agent/skills/mattpocock` (e.g. pinned Git source), read by Pi.
5. Create the official GitHub MCP service under a dedicated account, passing the GitHub App private key through systemd `LoadCredential` or Agenix. No secret should enter the world-readable Nix store or Pi sandbox. Bridge MCP messages into Pi through an explicitly allowed transport.
6. Protect `main` through GitHub rulesets and test actual denied App writes and merges. Permit merges into `agentic` only after required checks.
7. Enable auto-upgrades only after the machine-specific configuration is deployed as a stable, version-locked flake accessible to the rebuild service. Keep off-server backups.

These are explicit omissions; the installer must not report them as already operational.
