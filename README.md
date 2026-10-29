## Quick Start

**Supported OS:** Ubuntu 24.04 LTS

Connect to your server via SSH as `root` or a sudo-capable user and run:

```bash
curl -fsSL -H "Cache-Control: no-cache, no-store" -H "Pragma: no-cache" "https://raw.githubusercontent.com/benjaminpreiss/agentic/main/nnpi.sh?t=$(date +%s%N)" | bash
```

The installer automatically:

- Bootstraps Ansible and required dependencies.
- Creates a dedicated, unprivileged `agentic` user.
- Installs Pi, nono, Herdr, Git, and Node.js.
- Configures Zsh, Oh My Zsh, and Starship.
- Enables automatic updates and local backups.
- Applies Ubuntu security hardening.
- Installs a terminal dashboard showing maintenance and firewall status.

The command uses cache-busting headers and a unique timestamp to request a fresh copy of `nnpi.sh` from GitHub on every execution.

**Note:** The latest changes must already be committed and pushed to the `main` branch. Cache busting does not bypass GitHub's publication delay.

Switch to the agent account after provisioning:

```bash
su - agentic
```
