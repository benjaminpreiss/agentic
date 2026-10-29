# Agentic

**A secure, self-maintaining AI coding environment for Ubuntu servers.**

Deploy [Pi](https://github.com/badlogic/pi-mono), [nono](https://nono.sh), and [Herdr](https://herdr.dev) with a single command.

Powered by Ansible, with automatic updates, local backups, OS hardening, and a modern terminal dashboard.

## Quick Start

**Supported OS:** Ubuntu 24.04 LTS

SSH into your server as `root` or a sudo-capable user and run:

```bash
curl -fsSL https://raw.githubusercontent.com/benjaminpreiss/agentic/main/nnpi.sh | bash
```

The installer automatically:

- Bootstraps Ansible and required dependencies.
- Creates a dedicated, unprivileged `agentic` user.
- Installs Pi, nono, Herdr, Git, and Node.js.
- Configures Zsh, Oh My Zsh, and Starship.
- Enables automatic updates and local backups.
- Applies Ubuntu security hardening.
- Installs a terminal dashboard showing maintenance and firewall status.

Switch to the agent account:

```bash
su - agentic
```

Provisioning is designed to be rerunnable.

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

The terminal also includes tab completion, autosuggestions, syntax highlighting, and command history search.

## Running Pi

Start Pi inside the nono sandbox:

```bash
nnpi
```

Pass a prompt directly:

```bash
nnpi -p "Analyze this repository"
```

The `nnpi` command launches Pi through nono using the `pi-herdr` sandbox profile and enables Herdr agent detection.

### Connect with Herdr

From your local machine:

```bash
herdr machine add agentic@your-server
```

Ensure your SSH public key is authorized for the `agentic` account.

## Automatic Maintenance

Agentic is designed to run with minimal manual maintenance.

| Setting | Configuration |
|---|---|
| Ubuntu security updates | Automatic via unattended-upgrades |
| Agent tooling updates | Daily at 04:00 |
| Random update delay | Up to 30 minutes |
| Missed update windows | Run after downtime |
| Automatic reboot | Disabled by default |
| Maintenance logging | systemd journal |

Daily tooling maintenance covers Pi, Herdr, nono, Oh My Zsh, Starship, and related components.

### Local Backups

Before scheduled tooling updates, Agentic creates a compressed backup of the agent user's home directory.

| Setting | Configuration |
|---|---|
| Source | `/home/agentic/` |
| Destination | `/var/backups/agentic/` |
| Format | Compressed `.tar.gz` |
| Retention | Latest 14 backups |
| Access | Root only |
| Failure handling | Skip agent updates if backup fails |

Backups include hidden directories, Pi configuration, SSH keys, and workspaces stored in the home directory.

**Note:** These are local archives, not atomic filesystem snapshots. They do not protect against server or disk failure.

### Maintenance Commands

Check the maintenance schedule:

```bash
systemctl list-timers agentic-update.timer
```

View recent updates:

```bash
journalctl -u agentic-update.service -n 100
```

Run an update manually:

```bash
sudo systemctl start agentic-update.service
```

Create a backup:

```bash
sudo /usr/local/sbin/agentic-snapshot
```

List existing backups:

```bash
sudo ls -lh /var/backups/agentic/
```

## OS Security Hardening

The installer applies a conservative security baseline for Ubuntu 24.04 LTS.

| Protection | Configuration |
|---|---|
| UFW | Deny incoming, allow outgoing |
| SSH firewall rules | Automatically allow detected SSH ports |
| Fail2ban | Protect SSH against repeated login failures |
| SSH restrictions | Limit authentication attempts and login grace time |
| AppArmor | Enable available application confinement |
| Kernel hardening | Restrict kernel information exposure and unsafe filesystem operations |
| Network hardening | Disable ICMP redirects |
| Security reporting | Show protection status in the terminal dashboard |

### Firewall Configuration

By default, the firewall blocks unsolicited incoming traffic except for explicitly allowed services.

To allow an additional TCP port:

```bash
sudo ufw allow 8080/tcp
```

To allow a UDP port:

```bash
sudo ufw allow 51820/udp
```

Inspect the current rules:

```bash
sudo ufw status verbose
```

UFW rules persist across reboots.

To skip firewall activation during installation:

```bash
curl -fsSL https://raw.githubusercontent.com/benjaminpreiss/agentic/main/nnpi.sh | ENABLE_UFW=false bash
```

**SSH safety:** The installer preserves existing root login and password authentication settings. It permits detected SSH ports before enabling UFW, but you should still verify a second SSH connection before disconnecting your original session.

### Firewall Status Reporting

The Zsh welcome screen automatically displays the firewall's current inbound allow rules, including TCP, UDP, port ranges, and IPv6 rules where present.

A lightweight systemd service refreshes a read-only firewall report every two minutes. This allows the unprivileged `agentic` user to view the information without sudo access.

**Important:** An allowed firewall port does not necessarily mean an application is listening on it, or that a hosting provider's external firewall permits access.

## Terminal Dashboard

Every interactive Zsh session displays a welcome screen with installed tools, useful commands, maintenance information, and security status.

Example:

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

The dashboard uses actual system information and does not trigger maintenance operations on login.

Firewall status is cached and may be up to two minutes old.

## Configuration

The default agent username is `agentic`.

To use another username:

```bash
curl -fsSL https://raw.githubusercontent.com/benjaminpreiss/agentic/main/nnpi.sh | AGENT_USER=developer bash
```

To update the installation, push changes to `nnpi.sh` in GitHub and rerun the one-line command.

## Security Considerations

- Pi runs under a dedicated, unprivileged Linux account.
- The `nnpi` launcher executes Pi inside nono's sandbox.
- Ubuntu security updates and agent tooling updates are automated.
- Root-only backups provide local recovery points.
- UFW blocks unsolicited inbound traffic unless explicitly allowed.
- SSH brute-force protection is enabled through Fail2ban.
- Automatic reboots are disabled by default.
- Existing SSH authentication settings remain unchanged.
- Pi credentials must be configured separately.

Running `pi` directly bypasses the nono sandbox. Use `nnpi` for sandboxed agent sessions.

Local backups do not replace off-server backups. Automated updates can also introduce breaking changes or interrupt active processes.

The provisioning script has been syntax-validated but has not undergone full end-to-end testing on a production Ubuntu 24.04 server.

## Repository

[github.com/benjaminpreiss/agentic](https://github.com/benjaminpreiss/agentic)

## License

See [LICENSE](LICENSE), if provided.