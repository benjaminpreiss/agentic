# Agentic

**A secure, self-maintaining AI coding environment for Ubuntu servers.**

Deploy [Pi](https://github.com/badlogic/pi-mono), [nono](https://nono.sh), and [Herdr](https://herdr.dev) with a single command.

Powered by Ansible, with automatic updates, local backups, OS hardening, globally available AI skills, and a modern Zsh terminal.

## Quick Start

**Supported OS:** Ubuntu 24.04 LTS

Connect to your server via SSH as `root` or a sudo-capable user and run:

```bash
curl -fsSL -H "Cache-Control: no-cache, no-store" -H "Pragma: no-cache" "https://raw.githubusercontent.com/benjaminpreiss/agentic/main/nnpi.sh?t=$(date +%s%N)" | bash
```

The unique timestamp and HTTP headers help avoid cached copies of the installer. Changes must already be pushed to the `main` branch.

The installer:

- Bootstraps Ansible and creates an unprivileged `agentic` user.
- Installs Pi, nono, Herdr, Node.js 24, and Git.
- Installs all [Matt Pocock skills](https://github.com/mattpocock/skills) globally for Pi.
- Creates `/home/agentic/work` as the default workspace.
- Configures Zsh, Oh My Zsh, Starship, and terminal completion.
- Enables automated updates and backups.
- Applies Ubuntu security hardening and configures the terminal dashboard.

After installation, enter the agent environment:

```bash
sudo -iu agentic
```

If logged in as root, use `su - agentic`.

## Included Tools

| Component | Purpose |
|---|---|
| [Pi](https://github.com/badlogic/pi-mono) | AI coding agent |
| [nono](https://nono.sh) | Sandboxed agent execution |
| [Herdr](https://herdr.dev) | Remote agent session management |
| [Matt Pocock Skills](https://github.com/mattpocock/skills) | Global AI engineering skills |
| Ansible | Automated provisioning |
| Git | Version control |
| Node.js + npm | Pi runtime |
| Zsh + Oh My Zsh | Interactive shell and plugins |
| Starship | Modern terminal prompt |

## Workspace & AI Skills

The installer creates the workspace:

```text
/home/agentic/work/
```

Interactive Zsh login sessions automatically start in `~/work`. Existing files are preserved when provisioning is rerun.

### Matt Pocock Skills

All skills from the upstream repository are installed globally for the `agentic` user:

```text
/home/agentic/.pi/agent/skills/mattpocock/
```

Pi discovers these skills recursively, making them available from `~/work` and any other project directory.

Skills are updated automatically as part of daily maintenance using Git fast-forward updates.

Start Pi inside the workspace:

```bash
nnpi
```

Example skill commands, when available in the installed upstream version:

```text
/skill:ask-matt
/skill:setup-matt-pocock-skills
```

The setup skill can help configure Matt Pocock's workflow for individual projects.

### Sandboxed Execution

The `nnpi` launcher executes Pi inside nono using the `pi-herdr` profile and enables Herdr agent detection.

Run a prompt directly:

```bash
nnpi -p "Analyze this repository"
```

Arguments are forwarded to Pi. Running `pi` directly bypasses the nono sandbox.

## Remote Access with Herdr

From your local computer:

```bash
herdr machine add agentic@your-server
```

Ensure your SSH public key is authorized for the `agentic` account.

## Terminal Environment

The default login shell includes:

- Zsh with Oh My Zsh
- Starship's two-line prompt
- Tab completion and command autosuggestions
- Syntax highlighting and history search
- A welcome dashboard with tool, maintenance, and security status

### Ghostty Compatibility

When connecting through Ghostty over SSH, the installer checks whether the remote server recognizes `xterm-ghostty`.

If the terminal definition is missing, Zsh automatically falls back to `xterm-256color` to help avoid rendering artifacts and broken cursor positioning.

Inspect the terminal configuration:

```bash
echo "$TERM"
infocmp "$TERM"
```

## Automatic Maintenance

| Setting | Configuration |
|---|---|
| Ubuntu security updates | Automatic |
| Agent tooling and skills updates | Daily at 04:00 |
| Random delay | Up to 30 minutes |
| Missed updates | Run after server downtime |
| Automatic reboot | Disabled by default |
| Maintenance logs | systemd journal |

Maintenance covers Pi, Herdr, nono, Oh My Zsh, Starship, and Matt Pocock's skill repository.

### Local Backups

Before scheduled agent tooling updates, Agentic creates a compressed backup of the agent user's home directory.

| Setting | Configuration |
|---|---|
| Source | `/home/agentic/` |
| Destination | `/var/backups/agentic/` |
| Format | `.tar.gz` |
| Retention | Last 14 backups |
| Access | Root only |
| Failure handling | Skip agent updates if backup fails |

These archives also include Pi's global skills, configuration, and workspaces stored in the home directory.

Local backups do not protect against disk failure and do not provide atomic system rollback.

### Maintenance Commands

```bash
# Next scheduled update
systemctl list-timers agentic-update.timer

# Recent maintenance logs
journalctl -u agentic-update.service -n 100

# Trigger maintenance manually (requires sudo/root)
sudo systemctl start agentic-update.service

# Create a local backup
sudo /usr/local/sbin/agentic-snapshot

# List backups
sudo ls -lh /var/backups/agentic/
```

## OS Security Hardening

The installer applies a conservative Ubuntu 24.04 security baseline.

| Protection | Configuration |
|---|---|
| UFW firewall | Deny incoming, allow outgoing |
| SSH firewall rules | Allow detected SSH ports |
| Fail2ban | Protect SSH against repeated failed logins |
| SSH restrictions | Limit authentication attempts and login grace period |
| AppArmor | Enable available application confinement |
| Kernel hardening | Restrict kernel information exposure and unsafe filesystem behavior |
| Network hardening | Disable ICMP redirects |
| Security reporting | Display status in the terminal dashboard |

Existing SSH authentication settings are preserved to reduce the risk of losing remote access.

### Firewall Configuration

Allow additional ports when needed:

```bash
sudo ufw allow 8080/tcp
sudo ufw allow 51820/udp
```

Inspect firewall status:

```bash
sudo ufw status verbose
```

To skip firewall activation during provisioning:

```bash
curl -fsSL -H "Cache-Control: no-cache, no-store" -H "Pragma: no-cache" "https://raw.githubusercontent.com/benjaminpreiss/agentic/main/nnpi.sh?t=$(date +%s%N)" | ENABLE_UFW=false bash
```

Always verify a second SSH connection after enabling the firewall.

## Terminal Dashboard

The interactive Zsh welcome screen displays available tools, quick commands, maintenance status, and firewall information.

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

Workspace
  ~/work

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
  herdr --help         Herdr CLI help
  Tab                  Autocomplete
  Ctrl+R               Search command history
```

Actual values come from the server. Firewall status is refreshed periodically and may be up to two minutes old.

Allowed ports do not necessarily correspond to active listening services.

## Configuration

The default username is `agentic`.

To use a different username:

```bash
curl -fsSL -H "Cache-Control: no-cache, no-store" -H "Pragma: no-cache" "https://raw.githubusercontent.com/benjaminpreiss/agentic/main/nnpi.sh?t=$(date +%s%N)" | AGENT_USER=developer bash
```

Provisioning is designed to be rerunnable. Push changes to `nnpi.sh` in GitHub and rerun the installer to apply them.

## Security Considerations

- The agent runs under a dedicated, unprivileged Linux account.
- `nnpi` launches Pi inside nono's sandbox.
- Running `pi` directly bypasses sandbox protections.
- Ubuntu and agent tooling updates are automated.
- Backups are stored locally with root-only access.
- UFW and Fail2ban protect network access.
- Existing SSH authentication settings remain unchanged.
- Automatic reboots are disabled by default.
- Pi authentication must be configured separately.

The installer has been syntax-validated but has not been fully tested end-to-end on Ubuntu 24.04.

## Repository

[github.com/benjaminpreiss/agentic](https://github.com/benjaminpreiss/agentic)

## License

See [LICENSE](LICENSE), if provided.
