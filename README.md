# Agentic

**A secure, self-maintaining AI coding environment for Ubuntu servers.**

Deploy [Pi](https://github.com/badlogic/pi-mono), [nono](https://nono.sh), and [Herdr](https://herdr.dev) with a single command.

Powered by Ansible, with automatic updates, local backups, OS hardening, and a modern Zsh terminal.

## Quick Start

**Supported OS:** Ubuntu 24.04 LTS

Connect to your server via SSH as `root` or a sudo-capable user and run:

```bash
curl -fsSL -H "Cache-Control: no-cache, no-store" -H "Pragma: no-cache" "https://raw.githubusercontent.com/benjaminpreiss/agentic/main/nnpi.sh?t=$(date +%s%N)" | bash
```

The timestamp makes each request unique, while the HTTP headers request a fresh copy of the installer.

**Important:** The latest `nnpi.sh` must already be committed and pushed to `main`. Review the script before executing it, as it makes system-wide changes.

The installer automatically:

- Bootstraps Ansible and its dependencies.
- Creates a dedicated, unprivileged `agentic` user.
- Installs Pi, nono, Herdr, Git, and Node.js 24.
- Configures Zsh, Oh My Zsh, Starship, and command completion.
- Enables automatic updates and local backups.
- Applies Ubuntu security hardening.
- Configures a terminal dashboard with maintenance and firewall information.

Switch to the agent account:

```bash
sudo -iu agentic
```

If you're logged in as root:

```bash
su - agentic
```

The provisioning script is designed to be rerunnable.

## Included Tools

| Component | Purpose |
|---|---|
| [Pi](https://github.com/badlogic/pi-mono) | AI coding agent |
| [nono](https://nono.sh) | Sandboxed agent execution |
| [Herdr](https://herdr.dev) | Remote agent session management |
| Ansible | Automated provisioning |
| Git | Version control |
| Node.js + npm | Pi runtime |
| Zsh + Oh My Zsh | Interactive shell and plugins |
| Starship | Modern terminal prompt |

The terminal includes tab completion, command autosuggestions, syntax highlighting, and history search.

## Running Pi

Start Pi inside the nono sandbox:

```bash
nnpi
```

Pass a prompt directly:

```bash
nnpi -p "Analyze this repository"
```

The `nnpi` launcher forwards arguments to Pi through nono using the `pi-herdr` sandbox profile and enables Herdr agent detection.

### Remote Access with Herdr

From your local machine:

```bash
herdr machine add agentic@your-server
```

Ensure your SSH public key is authorized for the `agentic` account.

## Terminal Environment

The default shell is Zsh, configured with:

- Oh My Zsh and useful plugins
- Starship's modern two-line prompt
- Tab completion and command autosuggestions
- Syntax highlighting
- A welcome dashboard with installed tools and host status

### Ghostty Compatibility

The installer includes compatibility handling for [Ghostty](https://ghostty.org) terminals connecting over SSH.

If the remote server does not recognize `xterm-ghostty`, the Zsh configuration automatically falls back to `xterm-256color`.

This helps prevent terminal rendering issues such as duplicated characters, broken cursor positioning, and visual artifacts.

The welcome screen indicates when compatibility mode is active.

To inspect terminal support manually:

```bash
echo "$TERM"
infocmp "$TERM"
```

The fallback is applied only when the required Ghostty terminal definition is unavailable.

## Automatic Maintenance

Agentic is designed to run with minimal manual administration.

| Setting | Configuration |
|---|---|
| Ubuntu security updates | Automatic |
| Agent tooling updates | Daily at 04:00 |
| Random update delay | Up to 30 minutes |
| Missed update windows | Run after downtime |
| Automatic reboot | Disabled by default |
| Maintenance logs | systemd journal |

The scheduled maintenance updates Pi, Herdr, nono, Oh My Zsh, Starship, and related tooling.

### Local Backups

Before scheduled agent tooling updates, Agentic creates a compressed backup of the agent user's home directory.

| Setting | Configuration |
|---|---|
| Source | `/home/agentic/` |
| Destination | `/var/backups/agentic/` |
| Format | `.tar.gz` |
| Retention | Last 14 backups |
| Permissions | Root only |
| Backup failure | Skip agent tooling updates |

Backups include hidden directories, agent configuration, SSH keys, and workspaces stored in the user's home directory.

**Note:** These are local archives, not filesystem snapshots. They do not protect against disk failure and do not provide atomic system rollback.

### Maintenance Commands

Check the next scheduled update:

```bash
systemctl list-timers agentic-update.timer
```

View recent maintenance activity:

```bash
journalctl -u agentic-update.service -n 100
```

Start a maintenance run manually:

```bash
sudo systemctl start agentic-update.service
```

Create a manual backup:

```bash
sudo /usr/local/sbin/agentic-snapshot
```

List stored backups:

```bash
sudo ls -lh /var/backups/agentic/
```

## OS Security Hardening

The installer configures a conservative security baseline for Ubuntu 24.04 LTS.

| Protection | Configuration |
|---|---|
| UFW | Deny incoming, allow outgoing |
| SSH firewall rules | Allow detected SSH ports |
| Fail2ban | Protect SSH against repeated authentication failures |
| SSH restrictions | Limit authentication attempts and login grace period |
| AppArmor | Enable available application confinement |
| Kernel hardening | Restrict kernel information exposure and unsafe filesystem operations |
| Network hardening | Disable ICMP redirects |
| Security reporting | Display status in the terminal dashboard |

### Firewall Configuration

Allow an additional TCP port:

```bash
sudo ufw allow 8080/tcp
```

Allow a UDP port:

```bash
sudo ufw allow 51820/udp
```

Inspect firewall rules:

```bash
sudo ufw status verbose
```

Existing firewall rules are intended to be preserved across provisioning runs.

To skip firewall activation:

```bash
curl -fsSL -H "Cache-Control: no-cache, no-store" -H "Pragma: no-cache" "https://raw.githubusercontent.com/benjaminpreiss/agentic/main/nnpi.sh?t=$(date +%s%N)" | ENABLE_UFW=false bash
```

**SSH safety:** The installer preserves existing root-login and password-authentication settings. Always verify that a second SSH connection works after provisioning.

### Firewall Port Reporting

The welcome screen displays configured inbound UFW allow rules, including:

- TCP ports
- UDP ports
- Port ranges
- IPv6 rules where available

A lightweight systemd service refreshes the firewall status report every two minutes.

The `agentic` user can view this information without sudo privileges.

An allowed firewall port does not necessarily mean an application is listening on it or that an external hosting-provider firewall permits access.

## Terminal Dashboard

Each interactive Zsh session shows a welcome screen similar to:

```text
╭────────────────────────────────────────╮
│           AGENTIC WORKSPACE            │
╰────────────────────────────────────────╯

Available tools
  nnpi      Sandboxed Pi
  pi        Pi coding agent
  nono      Sandbox
  herdr     Remote agent sessions
  git       Version control

Maintenance
  Last update:       Successful
  Next update:       Tomorrow 04:00–04:30
  Latest backup:     Today 04:12
  Backup retention:  14 archives

Host security
  SSH protection:    Fail2ban enabled
  UFW firewall:      Enabled
  AppArmor:          Managed

Open firewall ports (UFW inbound allow rules)
  22/tcp
  51820/udp
  8080/tcp

Quick commands
  nnpi                 Start sandboxed Pi
  nnpi -p "prompt"     Run a prompt
  git status           Repository status
  Ctrl+R               Search command history
  Tab                  Autocomplete
```

The dashboard displays server information without initiating updates on login. Values above are examples.

## Configuration

The default agent username is `agentic`.

To use another username:

```bash
curl -fsSL -H "Cache-Control: no-cache, no-store" -H "Pragma: no-cache" "https://raw.githubusercontent.com/benjaminpreiss/agentic/main/nnpi.sh?t=$(date +%s%N)" | AGENT_USER=developer bash
```

To apply configuration changes, update `nnpi.sh` in GitHub and rerun the installation command.

## Security Considerations

- Pi runs under a dedicated, unprivileged user.
- `nnpi` executes Pi inside nono's sandbox.
- Running `pi` directly bypasses the sandbox.
- Ubuntu security updates and agent tooling updates are automated.
- Local backups are restricted to root.
- UFW blocks unsolicited inbound traffic unless explicitly allowed.
- Fail2ban protects SSH against repeated failed logins.
- Existing SSH authentication settings are preserved.
- Automatic reboots are disabled by default.
- Pi authentication must be configured separately.

Automated tool updates may introduce breaking changes, and local backups do not replace off-server backups.

The provisioning script has undergone syntax validation but has not been fully tested end-to-end on Ubuntu 24.04.

## Repository

[github.com/benjaminpreiss/agentic](https://github.com/benjaminpreiss/agentic)

## License

See [LICENSE](LICENSE), if provided.
