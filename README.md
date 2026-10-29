# Agentic

**A secure, self-maintaining AI coding environment for Ubuntu servers.**

Deploy [Pi](https://github.com/badlogic/pi-mono), [nono](https://nono.sh), and [Herdr](https://herdr.dev) with a single command.

Powered by Ansible, with automatic updates, local backups, OS hardening, globally available AI skills, and a modern Zsh terminal.

## Quick Start

**Supported OS:** Ubuntu 24.04 LTS

SSH into your server as `root` or a sudo-capable user and run:

```bash
curl -fsSL -H "Cache-Control: no-cache, no-store" -H "Pragma: no-cache" "https://raw.githubusercontent.com/benjaminpreiss/agentic/main/nnpi.sh?t=$(date +%s%N)" | bash
```

The timestamp and HTTP headers help avoid cached installer versions. Changes must already be committed and pushed to `main`.

The installer automatically:

- Bootstraps Ansible and creates a dedicated, unprivileged `agentic` user.
- Installs Pi, nono, Herdr, Git, and Node.js 24.
- Installs all [Matt Pocock skills](https://github.com/mattpocock/skills) globally for Pi.
- Creates `/home/agentic/work` as the designated workspace.
- Configures Zsh, Oh My Zsh, Starship, autocomplete, and a welcome dashboard.
- Enables daily automatic updates and local backups.
- Applies Ubuntu security hardening and firewall protections.

After installation, enter the agent account:

```bash
sudo -iu agentic
```

If logged in as root:

```bash
su - agentic
```

Provisioning is designed to be rerunnable without deleting existing workspaces or user configuration, except for installer-managed configuration files.

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

## Workspace

The installer creates:

```text
/home/agentic/work/
```

This directory is owned by `agentic` and is the designated location for running sandboxed Pi sessions.

**Neither SSH, Zsh, nor `nnpi` automatically changes your working directory.**

Navigate to the workspace explicitly:

```bash
cd ~/work
```

Or enter an existing project:

```bash
cd ~/work/my-project
```

The `nnpi` launcher preserves your current directory. If invoked outside `~/work`, it exits with an explanatory message rather than silently changing directories.

## Running Pi

Pi is installed globally using the maintained npm package:

```bash
npm install -g @earendil-works/pi-coding-agent
```

The installer automatically removes the deprecated `@mariozechner/pi-coding-agent` package when migrating an existing installation.

Pi settings, sessions, extensions, and globally installed skills are stored under:

```text
~/.pi/agent/
```

### Start a Sandboxed Session

Navigate to your workspace:

```bash
cd ~/work
nnpi
```

Or start Pi inside an existing project:

```bash
cd ~/work/my-project
nnpi
```

Execute a prompt directly:

```bash
nnpi -p "Analyze this repository"
```

If launched outside the workspace, `nnpi` explains the restriction:

```text
nnpi: Pi can run only inside the sandboxed workspace: /home/agentic/work
Switch there with: cd ~/work
```

Running `pi` directly bypasses the nono sandbox. Use `nnpi` for sandboxed agent execution.

### Authentication

Pi requires authentication with a supported model provider.

Start Pi using `nnpi`, then run:

```text
/login
```

Follow the instructions to configure your preferred provider using OAuth or an API key.

Authentication is not configured automatically.

## Sandboxed Execution

The `nnpi` launcher executes Pi inside [nono](https://nono.sh) using a custom `pi-herdr` profile.

The profile inherits the official `nolabs-ai/pi` policy instead of maintaining a separate credential denylist.

### Filesystem Permissions

| Location | Access |
|---|---|
| `~/work` | Read/write |
| `~/.pi/agent/skills` | Explicit read-only grant |
| Pi configuration and session data | Inherited from `nolabs-ai/pi` |
| Other locations | Governed by inherited nono policy |

The inherited profile provides runtime permissions and sensitive-path protections.

**Important:** Inherited filesystem permissions are additive. The read-only skills grant does not override broader inherited permissions to `~/.pi`.

The workspace restriction is enforced by the launcher. It does not prevent users from launching Pi directly outside the sandbox.

### JITI Extension Compatibility

Pi uses `jiti` to load TypeScript extensions, including the Herdr and nono integrations.

The `nnpi` launcher sets:

```bash
export JITI_FS_CACHE=false
```

This prevents jiti from accessing its filesystem cache under `/tmp/jiti`, which would otherwise cause permission errors inside nono.

The fix is applied automatically every time `nnpi` starts, without granting broader access to `/tmp`.

## Matt Pocock Skills

All skills from [mattpocock/skills](https://github.com/mattpocock/skills) are installed globally for the `agentic` user:

```text
~/.pi/agent/skills/mattpocock/
```

Pi discovers these skills recursively, making them available from any project inside the workspace.

The skills are updated automatically during daily maintenance using Git fast-forward updates.

Example commands, depending on the installed upstream version:

```text
/skill:ask-matt
/skill:setup-matt-pocock-skills
```

The setup skill can be used to configure Matt Pocock's engineering workflow within individual projects.

## Remote Access with Herdr

Herdr enables remote session management and agent integration.

From your local machine, connect through SSH:

```bash
herdr machine add agentic@your-server
```

Ensure your SSH public key is authorized for the `agentic` account.

The installer configures Herdr's Pi integration. The `nnpi` launcher sets:

```bash
HERDR_AGENT=pi
```

This allows Herdr to recognize Pi when launched through nono.

Some Herdr connection workflows may also require the separate `hc` executable on the remote server. Verify its availability if your local client reports that it is missing.

## Terminal Environment

The default shell is Zsh, configured with:

- Oh My Zsh and productivity plugins
- Starship's modern two-line prompt
- Tab completion
- Autosuggestions and syntax highlighting
- Command history search
- A welcome dashboard with system status

### Welcome Screen

The dashboard appears once per interactive shell session, including interactive non-login Zsh sessions opened through SSH or Herdr.

It does not automatically change directories.

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

Workspace
  Directory:  ~/work
  Enter:      cd ~/work

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
  cd ~/work            Enter agent workspace
  nnpi                 Start sandboxed Pi
  nnpi -p "prompt"     Run a prompt
  herdr --help         Herdr CLI help
  Tab                  Autocomplete
  Ctrl+R               Search command history
```

All maintenance and firewall values above are examples. Actual information comes from the server.

To suppress the welcome screen, set `NNPI_NO_WELCOME=1` before launching Zsh.

### Ghostty Compatibility

When connecting using [Ghostty](https://ghostty.org) over SSH, the installer checks whether the server supports the `xterm-ghostty` terminal definition.

If it is missing, the shell falls back to `xterm-256color`.

This helps prevent rendering artifacts, duplicate characters, and incorrect cursor positioning caused by missing terminal capability definitions.

Check terminal support:

```bash
echo "$TERM"
infocmp "$TERM"
```

The fallback is applied only when necessary.

## Automatic Maintenance

Agentic is designed for minimal manual administration.

| Setting | Configuration |
|---|---|
| Ubuntu package updates | Automatic |
| Pi, Herdr, nono, and skill updates | Daily at 04:00 |
| Random scheduling delay | Up to 30 minutes |
| Missed maintenance | Run after downtime |
| Automatic reboot | Disabled by default |
| Logs | systemd journal |

The daily maintenance process updates:

- Ubuntu packages using APT and unattended-upgrades
- Pi (`@earendil-works/pi-coding-agent`)
- Herdr
- nono and its Pi sandbox package
- Oh My Zsh
- Starship
- Matt Pocock's skills repository

### Local Backups

Before scheduled maintenance, Agentic creates a compressed backup of the agent user's home directory.

| Setting | Configuration |
|---|---|
| Source | `/home/agentic/` |
| Destination | `/var/backups/agentic/` |
| Format | `.tar.gz` |
| Retention | Latest 14 archives |
| Permissions | Root only |
| Backup failure | Maintenance updates skipped |

Backups include workspaces, Pi configuration, sessions, extensions, skills, and other files inside the agent user's home directory.

These are local recovery archives, not atomic filesystem snapshots. They do not protect against disk failure or guarantee rollback of system-wide packages.

### Maintenance Commands

Check the next scheduled maintenance run:

```bash
systemctl list-timers agentic-update.timer
```

View recent maintenance activity:

```bash
journalctl -u agentic-update.service -n 100
```

Run maintenance manually:

```bash
sudo systemctl start agentic-update.service
```

Create a manual backup:

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
| UFW firewall | Deny incoming, allow outgoing |
| SSH rules | Allow detected SSH ports before enabling UFW |
| Fail2ban | Protect SSH against repeated failed logins |
| SSH restrictions | Limit authentication attempts and login grace period |
| AppArmor | Enable available application confinement |
| Kernel hardening | Restrict kernel information and unsafe filesystem operations |
| Network hardening | Disable ICMP redirects |
| Security reporting | Show status in the terminal dashboard |

Existing SSH authentication settings are preserved to reduce the risk of losing remote access.

### Firewall Configuration

Allow an additional TCP port:

```bash
sudo ufw allow 8080/tcp
```

Allow a UDP port:

```bash
sudo ufw allow 51820/udp
```

Inspect the firewall:

```bash
sudo ufw status verbose
```

Existing UFW rules are intended to remain intact across provisioning runs.

To skip firewall activation:

```bash
curl -fsSL -H "Cache-Control: no-cache, no-store" -H "Pragma: no-cache" "https://raw.githubusercontent.com/benjaminpreiss/agentic/main/nnpi.sh?t=$(date +%s%N)" | ENABLE_UFW=false bash
```

After provisioning, verify that a second SSH connection works before disconnecting your original session.

### Firewall Port Reporting

The welcome dashboard displays UFW's configured inbound allow rules, including TCP ports, UDP ports, port ranges, and IPv6 entries where available.

A lightweight systemd service refreshes the firewall report every two minutes.

The `agentic` user can read the report without elevated privileges.

An allowed firewall port does not necessarily mean an application is listening on it or that an external provider firewall permits access.

## Configuration

The default agent username is `agentic`.

To use another username:

```bash
curl -fsSL -H "Cache-Control: no-cache, no-store" -H "Pragma: no-cache" "https://raw.githubusercontent.com/benjaminpreiss/agentic/main/nnpi.sh?t=$(date +%s%N)" | AGENT_USER=developer bash
```

The installer supports execution as root or as a sudo-capable user.

Configuration changes are applied by updating `nnpi.sh` in GitHub and rerunning the installer.

## Security Considerations

- Pi runs under a dedicated, unprivileged Linux account.
- `nnpi` executes Pi inside nono's sandbox.
- Pi's designated writable project workspace is `~/work`.
- The launcher never silently changes directories.
- Additional permissions are inherited from nono's official Pi profile.
- Running `pi` directly bypasses sandbox protections.
- Automatic system and agent-tool updates are enabled.
- Backups are stored locally with root-only access.
- UFW and Fail2ban provide network protections.
- Existing SSH authentication settings are preserved.
- Automatic reboots are disabled by default.
- Pi authentication must be configured separately.

Automated updates may introduce breaking changes or disrupt active processes. Local backups should not replace off-server backups.

The provisioning script has undergone syntax validation but has not been fully tested end-to-end on Ubuntu 24.04 LTS.

## Repository

[github.com/benjaminpreiss/agentic](https://github.com/benjaminpreiss/agentic)

## License

See [LICENSE](LICENSE), if provided.
