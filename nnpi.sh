#!/usr/bin/env bash
set -Eeuo pipefail

echo "nnpi bootstrap revision: 2026-10-29-nono-profile-check-fix-v2"

# Ubuntu 24.04 LTS. Run as root or as a user with sudo rights.
if [[ "$(. /etc/os-release; echo "${ID}:${VERSION_ID}")" != 'ubuntu:24.04' ]]; then
  echo 'This bootstrap supports only Ubuntu 24.04 LTS.' >&2
  exit 1
fi
AGENT_USER="${AGENT_USER:-agentic}"
if [[ ! "$AGENT_USER" =~ ^[a-z_][a-z0-9_-]*$ ]] || [[ "$AGENT_USER" == root ]]; then
  echo 'AGENT_USER must be a valid lowercase non-root Linux username.' >&2
  exit 1
fi
# Do not attempt to re-execute stdin as root: curl | bash has no reusable script path.
# Instead elevate only package installation and the Ansible playbook.
if [[ "$(id -u)" -eq 0 ]]; then
  PRIV=()
  SSH_SOURCE_USER=root
else
  command -v sudo >/dev/null || { echo 'sudo is required for non-root execution.' >&2; exit 1; }
  sudo -v  # Prompts once if the invoking user needs a sudo password.
  PRIV=(sudo)
  SSH_SOURCE_USER="$(id -un)"
fi
# AUTO_REBOOT=true schedules a reboot at REBOOT_TIME when required, unless
# users are logged in. Default is false to protect active remote sessions.
AUTO_REBOOT="${AUTO_REBOOT:-false}"
REBOOT_TIME="${REBOOT_TIME:-04:00}"
if [[ ! "$AUTO_REBOOT" =~ ^(true|false)$ ]] || [[ ! "$REBOOT_TIME" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
  echo 'AUTO_REBOOT must be true/false and REBOOT_TIME must be HH:MM.' >&2
  exit 1
fi
ENABLE_UFW="${ENABLE_UFW:-true}"
if [[ ! "$ENABLE_UFW" =~ ^(true|false)$ ]]; then
  echo 'ENABLE_UFW must be true or false.' >&2; exit 1
fi
export AGENT_USER SSH_SOURCE_USER AUTO_REBOOT REBOOT_TIME ENABLE_UFW DEBIAN_FRONTEND=noninteractive NEEDRESTART_SUSPEND=1 NEEDRESTART_MODE=l
"${PRIV[@]}" env DEBIAN_FRONTEND=noninteractive NEEDRESTART_SUSPEND=1 NEEDRESTART_MODE=l apt-get update
"${PRIV[@]}" env DEBIAN_FRONTEND=noninteractive NEEDRESTART_SUSPEND=1 NEEDRESTART_MODE=l apt-get install -y ansible-core sudo ca-certificates curl zsh procps
# Prepare shared status directory before Ansible writes status files.
"${PRIV[@]}" install -d -o root -g root -m 0755 /var/lib/agentic

playbook="$(mktemp --suffix=.yml)"
trap 'rm -f "$playbook"' EXIT
cat > "$playbook" <<'YAML'
---
- name: Create isolated agent account
  hosts: localhost
  connection: local
  gather_facts: false
  vars:
    agent_user: "{{ lookup('env', 'AGENT_USER') }}"
    agent_home: "/home/{{ agent_user }}"
    ssh_source_user: "{{ lookup('env', 'SSH_SOURCE_USER') }}"
  tasks:
    - name: Create non-privileged agent user
      ansible.builtin.user:
        name: "{{ agent_user }}"
        home: "{{ agent_home }}"
        create_home: true
        shell: /usr/bin/zsh
        state: present
    - name: Check existing SSH authorized keys from invoking account
      ansible.builtin.stat:
        path: "{{ '/root' if ssh_source_user == 'root' else '/home/' + ssh_source_user }}/.ssh/authorized_keys"
      register: source_keys
    - name: Create SSH directory for agent user
      ansible.builtin.file:
        path: "{{ agent_home }}/.ssh"
        state: directory
        owner: "{{ agent_user }}"
        group: "{{ agent_user }}"
        mode: '0700'
      when: source_keys.stat.exists
    - name: Copy existing root SSH authorized keys if agent user has none
      ansible.builtin.copy:
        src: "{{ '/root' if ssh_source_user == 'root' else '/home/' + ssh_source_user }}/.ssh/authorized_keys"
        dest: "{{ agent_home }}/.ssh/authorized_keys"
        remote_src: true
        owner: "{{ agent_user }}"
        group: "{{ agent_user }}"
        mode: '0600'
        force: false
      when: source_keys.stat.exists

- name: Provision Herdr, Pi and nono as agent user
  hosts: localhost
  connection: local
  gather_facts: false
  become: true
  become_method: sudo
  become_user: "{{ lookup('env', 'AGENT_USER') }}"
  vars:
    user_home: "/home/{{ lookup('env', 'AGENT_USER') }}"
    local_bin: "{{ user_home }}/.local/bin"
    agent_dir: "{{ user_home }}/.pi/agent"
    provision_path: "{{ local_bin }}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
  environment:
    HOME: "{{ user_home }}"
    PATH: "{{ provision_path }}"
    DEBIAN_FRONTEND: noninteractive
    NEEDRESTART_SUSPEND: "1"
    NEEDRESTART_MODE: l
  tasks:
    - name: Install prerequisite OS packages
      become_user: root
      ansible.builtin.apt:
        name: [curl, ca-certificates, gnupg, git, procps, xz-utils, zsh, zsh-autosuggestions, zsh-syntax-highlighting, fonts-powerline]
        state: present
        update_cache: true

    # Update metadata daily, but apply packages in the daily backed-up maintenance window.
    # A separate higher-numbered apt configuration file survives package upgrades.
    - name: Install automatic update packages
      become_user: root
      ansible.builtin.apt:
        name: [unattended-upgrades, update-notifier-common]
        state: present

    - name: Enable daily APT metadata downloads (upgrades occur after daily backup)
      become_user: root
      ansible.builtin.copy:
        dest: /etc/apt/apt.conf.d/20auto-upgrades
        owner: root
        group: root
        mode: '0644'
        content: |
          APT::Periodic::Update-Package-Lists "1";
          APT::Periodic::Download-Upgradeable-Packages "1";
          APT::Periodic::Unattended-Upgrade "0";
          APT::Periodic::AutocleanInterval "7";

    - name: Configure automatic Ubuntu upgrades, cleanup and reboot policy
      become_user: root
      ansible.builtin.copy:
        dest: /etc/apt/apt.conf.d/90-agentic-unattended-upgrades
        owner: root
        group: root
        mode: '0644'
        content: |
          // Include regular stable Ubuntu updates in addition to the stock
          // security and ESM origins. Third-party repositories are not enabled.
          Unattended-Upgrade::Allowed-Origins {
            "${distro_id}:${distro_codename}-updates";
          };
          Unattended-Upgrade::Remove-Unused-Dependencies "true";
          Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
          Unattended-Upgrade::Automatic-Reboot "{{ lookup('env', 'AUTO_REBOOT') }}";
          Unattended-Upgrade::Automatic-Reboot-WithUsers "false";
          Unattended-Upgrade::Automatic-Reboot-Time "{{ lookup('env', 'REBOOT_TIME') }}";

    - name: Enable APT metadata/update timers
      become_user: root
      ansible.builtin.systemd_service:
        name: "{{ item }}"
        enabled: true
        state: started
      loop:
        - apt-daily.timer
        - apt-daily-upgrade.timer

    - name: Check whether Oh My Zsh is installed
      ansible.builtin.stat:
        path: "{{ user_home }}/.oh-my-zsh/oh-my-zsh.sh"
      register: omz_installed

    - name: Install Oh My Zsh non-interactively for agent user
      ansible.builtin.shell: |
        set -euo pipefail
        curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh | RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh
      args: {executable: /bin/bash}
      when: not omz_installed.stat.exists

    - name: Install Starship prompt system-wide
      become_user: root
      ansible.builtin.shell: |
        set -euo pipefail
        curl -fsSL https://starship.rs/install.sh | sh -s -- -y -b /usr/local/bin
      args: {executable: /bin/bash, creates: /usr/local/bin/starship}

    - name: Create prompt configuration directory
      ansible.builtin.file:
        path: "{{ user_home }}/.config"
        state: directory
        mode: '0755'

    - name: Set up Zsh configuration and shell completion
      ansible.builtin.copy:
        dest: "{{ user_home }}/.zshrc"
        mode: '0644'
        # This account is dedicated to agent sessions; its shell config is managed.
        content: |
          export PATH="$HOME/.local/bin:$PATH"
          export ZSH="$HOME/.oh-my-zsh"
          ZSH_THEME=""
          plugins=(git sudo)
          source "$ZSH/oh-my-zsh.sh"
          autoload -Uz compinit
          compinit
          zstyle ':completion:*' menu select
          zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
          [[ -r /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]] && source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
          [[ -r /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] && source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
          command -v starship >/dev/null && eval "$(starship init zsh)"

          # Welcome message for interactive login shells (never automated commands).
          if [[ -o interactive && -o login && -z "${NNPI_NO_WELCOME:-}" ]]; then
            print -P '%F{cyan}╭────────────────────────────────────────╮%f'
            print -P '%F{cyan}│           AGENTIC WORKSPACE            │%f'
            print -P '%F{cyan}╰────────────────────────────────────────╯%f'
            print ''
            print 'Available tools:'
            for tool in nnpi pi nono herdr git node npm ansible-playbook; do
              if (( $+commands[$tool] )); then
                printf '  %-17s %s\n' "$tool" "$(command -v "$tool")"
              fi
            done
            print ''
            print 'Maintenance status:'
            if (( $+commands[systemctl] )); then
              local next_run last_run service_result service_exit
              next_run="$(systemctl show agentic-update.timer -p NextElapseUSecRealtime --value 2>/dev/null)"
              last_run="$(systemctl show agentic-update.service -p ExecMainExitTimestamp --value 2>/dev/null)"
              service_result="$(systemctl show agentic-update.service -p Result --value 2>/dev/null)"
              service_exit="$(systemctl show agentic-update.service -p ExecMainStatus --value 2>/dev/null)"
              [[ -n "$next_run" && "$next_run" != n/a ]] && print "  Next maintenance: $next_run" || print '  Next maintenance: not scheduled'
              if [[ -n "$last_run" && "$last_run" != n/a ]]; then
                if [[ "$service_result" == success && "$service_exit" == 0 ]]; then
                  print -P "  Last maintenance: %F{green}OK%f ($last_run)"
                else
                  print -P "  Last maintenance: %F{red}${service_result:-unknown}%f (exit ${service_exit:-?}; $last_run)"
                fi
              else
                print '  Last maintenance: not run yet'
              fi
            else
              print '  Maintenance service: systemd unavailable'
            fi
            if [[ -r /var/lib/agentic/last-backup ]]; then
              print "  Latest backup: $(</var/lib/agentic/last-backup)"
            else
              print '  Latest backup: not recorded yet'
            fi
            print '  Backup retention: 14 archives (root-only)'
            if [[ -r /var/lib/agentic/hardening-status ]]; then
              print ''
              print 'Host security:'
              while IFS= read -r status_line; do print "  $status_line"; done < /var/lib/agentic/hardening-status
            fi
            print ''
            print 'Open firewall ports (UFW inbound allow rules):'
            if [[ -r /var/lib/agentic/firewall-status ]]; then
              while IFS= read -r firewall_line; do print "  $firewall_line"; done < /var/lib/agentic/firewall-status
            else
              print '  Status not available yet'
            fi
            print ''
            print 'Quick commands:'
            print '  nnpi                 Start Pi inside nono sandbox (Herdr-aware)'
            print '  nnpi -p "prompt"     Run a prompt non-interactively'
            print '  pi                   Start Pi directly (NOT sandboxed)'
            print '  nono run --profile pi-herdr --dry-run -- /usr/bin/true  Check sandbox profile'
            print '  herdr --help         Herdr CLI help'
            print '  git status           Inspect the current repository'
            print '  Tab                  Complete files and commands'
            print '  Ctrl+R               Search shell history'
            print ''
          fi

    - name: Give Starship a clean two-line prompt with Git branch and status
      ansible.builtin.copy:
        dest: "{{ user_home }}/.config/starship.toml"
        mode: '0644'
        content: |
          add_newline = true
          format = "$username$hostname$directory$git_branch$git_status$nodejs$python$cmd_duration$line_break$character"
          [username]
          show_always = true
          style_user = "bold cyan"
          format = "[$user]($style)@"
          [hostname]
          ssh_only = false
          style = "bold blue"
          format = "[$hostname]($style) "
          [directory]
          truncation_length = 3
          style = "bold purple"
          [character]
          success_symbol = "[❯](bold green)"
          error_symbol = "[❯](bold red)"
          [cmd_duration]
          min_time = 2000
          format = " took [$duration](yellow)"

    - name: Check Node.js version
      ansible.builtin.command: node --version
      register: current_node
      changed_when: false
      failed_when: false

    # NodeSource is configured directly: do not run setup_24.x, which invokes
    # nested APT commands and can get stuck in interactive needrestart dialogs.
    - name: Download NodeSource repository signing key
      become_user: root
      ansible.builtin.get_url:
        url: https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key
        dest: /usr/share/keyrings/nodesource-repo.asc
        mode: '0644'
        timeout: 30
      when: current_node.rc != 0 or (current_node.stdout | regex_replace('^v', '')).split('.')[0] | int < 24

    - name: Configure NodeSource 24 APT source (without setup script)
      become_user: root
      ansible.builtin.copy:
        dest: /etc/apt/sources.list.d/nodesource.sources
        mode: '0644'
        content: |
          Types: deb
          URIs: https://deb.nodesource.com/node_24.x
          Suites: nodistro
          Components: main
          Signed-By: /usr/share/keyrings/nodesource-repo.asc
      when: current_node.rc != 0 or (current_node.stdout | regex_replace('^v', '')).split('.')[0] | int < 24

    - name: Prefer NodeSource nodejs package over Ubuntu Node.js
      become_user: root
      ansible.builtin.copy:
        dest: /etc/apt/preferences.d/agentic-nodejs
        mode: '0644'
        content: |
          Package: nodejs
          Pin: origin deb.nodesource.com
          Pin-Priority: 600
      when: current_node.rc != 0 or (current_node.stdout | regex_replace('^v', '')).split('.')[0] | int < 24

    - name: Install Node.js 24 from configured repository
      become_user: root
      ansible.builtin.apt:
        name: nodejs
        state: latest
        update_cache: true
        lock_timeout: 180
      when: current_node.rc != 0 or (current_node.stdout | regex_replace('^v', '')).split('.')[0] | int < 24

    - name: Verify Node.js 24 is available
      ansible.builtin.command: node --version
      register: node_verified
      changed_when: false
      failed_when: node_verified.rc != 0 or ((node_verified.stdout | regex_replace('^v', '')).split('.')[0] | int) < 24

    - name: Create user-level binary and Pi configuration directories
      ansible.builtin.file:
        path: "{{ item }}"
        state: directory
        mode: '0755'
      loop:
        - "{{ local_bin }}"
        - "{{ agent_dir }}"

    - name: Install Pi harness globally
      become_user: root
      ansible.builtin.command: npm install --global @mariozechner/pi-coding-agent
      environment:
        PATH: /usr/local/bin:/usr/bin:/bin
      register: pi_install
      changed_when: "'added ' in pi_install.stdout or 'changed ' in pi_install.stdout"

    - name: Check Herdr installation
      ansible.builtin.shell: command -v herdr
      args: {executable: /bin/bash}
      register: herdr_present
      failed_when: false
      changed_when: false

    - name: Install Herdr in agent user's home
      ansible.builtin.shell: |
        set -euo pipefail
        curl -fsSL https://herdr.dev/install.sh | sh
      args: {executable: /bin/bash}
      when: herdr_present.rc != 0

    - name: Ensure Herdr binary available on user PATH
      ansible.builtin.shell: |
        set -e
        binary="$(command -v herdr || find "$HOME/.local" "$HOME/.herdr" -type f -name herdr -perm /111 -print -quit 2>/dev/null | head -1)"
        test -n "$binary"
        if [ ! -e "$HOME/.local/bin/herdr" ]; then ln -s "$binary" "$HOME/.local/bin/herdr"; fi
      args: {executable: /bin/bash}
      changed_when: false

    - name: Check nono installation
      ansible.builtin.shell: command -v nono
      args: {executable: /bin/bash}
      register: nono_present
      failed_when: false
      changed_when: false

    - name: Install nono in agent user's home
      ansible.builtin.shell: |
        set -euo pipefail
        curl -fsSL https://nono.sh/install.sh | sh
      args: {executable: /bin/bash}
      when: nono_present.rc != 0

    - name: Find installed nono binary
      ansible.builtin.shell: |
        set -e
        command -v nono || find "$HOME/.local" -type f -name nono -perm /111 -print -quit
      args: {executable: /bin/bash}
      register: nono_path
      changed_when: false
      failed_when: nono_path.stdout | trim == ''

    - name: Make nono executable available from local bin
      ansible.builtin.file:
        src: "{{ nono_path.stdout | trim }}"
        dest: "{{ local_bin }}/nono"
        state: link
      when: (nono_path.stdout | trim) != (local_bin + '/nono')

    - name: Pull reviewed Pi sandbox package
      ansible.builtin.command: "{{ nono_path.stdout | trim }} pull nolabs-ai/pi"
      changed_when: false

    - name: Check local child profile
      ansible.builtin.stat:
        path: "{{ user_home }}/.config/nono/profiles/pi-herdr.json"
      register: child_profile

    - name: Create local profile extending the nono Pi package
      ansible.builtin.command: "{{ nono_path.stdout | trim }} profile init pi-herdr --extends nolabs-ai/pi"
      when: not child_profile.stat.exists

    - name: Install Pi extension for reporting status to Herdr
      ansible.builtin.command: "{{ local_bin }}/herdr integration install pi"
      register: integration_install
      changed_when: true
      # Use full path when Herdr's installer puts its binary into ~/.local/bin.

    - name: Install sandboxed Pi launcher with argument forwarding
      ansible.builtin.copy:
        dest: "{{ local_bin }}/nnpi"
        mode: '0755'
        content: |
          #!/usr/bin/env bash
          set -euo pipefail
          export HERDR_AGENT=pi
          exec "$(command -v nono)" run --profile pi-herdr -- "$(command -v pi)" "$@"

    - name: Add user's local bin to interactive shells' PATH
      ansible.builtin.blockinfile:
        path: "{{ user_home }}/.profile"
        create: true
        marker: '# {mark} HERDR PI NONO PATH'
        block: |
          case ":$PATH:" in
            *":$HOME/.local/bin:"*) ;;
            *) export PATH="$HOME/.local/bin:$PATH" ;;
          esac

    - name: Create protected local backup storage
      become_user: root
      ansible.builtin.file:
        path: /var/backups/agentic
        state: directory
        owner: root
        group: root
        mode: '0700'

    - name: Install pre-update agent home backup helper
      become_user: root
      ansible.builtin.copy:
        dest: /usr/local/sbin/agentic-snapshot
        owner: root
        group: root
        mode: '0750'
        content: |
          #!/usr/bin/env bash
          set -euo pipefail
          umask 077
          export DEBIAN_FRONTEND=noninteractive NEEDRESTART_SUSPEND=1 NEEDRESTART_MODE=l
          AGENT_USER="{{ lookup('env', 'AGENT_USER') }}"
          AGENT_HOME="/home/$AGENT_USER"
          STORE=/var/backups/agentic
          KEEP="${AGENTIC_BACKUP_KEEP:-14}"
          [[ "$KEEP" =~ ^[1-9][0-9]*$ ]] || { echo 'AGENTIC_BACKUP_KEEP must be a positive integer' >&2; exit 1; }
          [[ -d "$AGENT_HOME" && ! -L "$AGENT_HOME" ]] || { echo "Agent home missing or symlinked: $AGENT_HOME" >&2; exit 1; }
          install -d -m 0700 -o root -g root "$STORE"
          # Only back up the agent's home folder, not the OS or global packages.
          # Backups are complete home-directory archives, including hidden files.
          # They may contain authentication tokens and API keys: root-only storage.
          home_kib="$(du -skx "$AGENT_HOME" | awk '{print $1}')"
          available_kib="$(df -Pk "$STORE" | awk 'END {print $4}')"
          # Conservative disk-space check; compressed archives are usually smaller.
          required_kib=$((home_kib + 1048576))
          (( available_kib >= required_kib )) || {
            echo "Insufficient free space for home backup: need ${required_kib} KiB, have ${available_kib} KiB" >&2
            exit 1
          }
          stamp="$(date -u +%Y%m%dT%H%M%SZ)"
          stem="$STORE/agent-home-$stamp-$$"
          tmp="$stem.tar.gz.partial"
          dest="$stem.tar.gz"
          trap 'rm -f -- "$tmp"' EXIT
          tar -C /home -czpf "$tmp" --one-file-system "$AGENT_USER"
          gzip -t "$tmp"
          mv -- "$tmp" "$dest"
          sha256sum "$dest" > "$dest.sha256"
          echo "Created local agent home backup: $dest"
          # Expose only the successful backup timestamp to the unprivileged welcome screen.
          install -d -m 0755 -o root -g root /var/lib/agentic
          printf '%s UTC\n' "$stamp" > /var/lib/agentic/last-backup.tmp
          chmod 0644 /var/lib/agentic/last-backup.tmp
          mv -f /var/lib/agentic/last-backup.tmp /var/lib/agentic/last-backup
          # Delete older managed backups only after a new one succeeds.
          mapfile -t old < <(find "$STORE" -maxdepth 1 -type f -name 'agent-home-*.tar.gz' -printf '%f\n' | sort -r | tail -n +"$((KEEP + 1))")
          for name in "${old[@]}"; do
            rm -f -- "$STORE/$name" "$STORE/$name.sha256"
          done

    - name: Install daily agentic tooling updater
      become_user: root
      ansible.builtin.copy:
        dest: /usr/local/sbin/agentic-update
        owner: root
        group: root
        mode: '0750'
        content: |
          #!/usr/bin/env bash
          set -uo pipefail
          export DEBIAN_FRONTEND=noninteractive
          export DEBIAN_FRONTEND=noninteractive NEEDRESTART_SUSPEND=1 NEEDRESTART_MODE=l
          AGENT_USER="{{ lookup('env', 'AGENT_USER') }}"
          AGENT_HOME="/home/$AGENT_USER"
          failed=0
          exec 9>/run/agentic-update.lock
          flock -n 9 || { echo 'Another agentic update is running' >&2; exit 1; }
          # Fail closed: never update OS or tooling when recovery archive fails.
          /usr/local/sbin/agentic-snapshot || { echo 'Pre-update agent home backup failed; cancelling updates' >&2; exit 1; }
          log() { printf '[%s] %s\n' "$(date -Is)" "$*"; }
          step() {
            local label="$1"; shift
            log "Starting: $label"
            if "$@"; then log "OK: $label"; else
              log "FAILED: $label"; failed=1
            fi
          }
          as_agent() {
            runuser -u "$AGENT_USER" -- env HOME="$AGENT_HOME" PATH="$AGENT_HOME/.local/bin:/usr/local/bin:/usr/bin:/bin" "$@"
          }
          update_pi() { npm install -g @mariozechner/pi-coding-agent@latest; }
          update_herdr() { as_agent herdr update; }
          update_nono() {
            local installer
            installer="$(mktemp)" || return 1
            if ! curl --proto '=https' --tlsv1.2 -fsSL https://nono.sh/install.sh -o "$installer"; then
              rm -f "$installer"; return 1
            fi
            chmod 0755 "$installer"
            as_agent sh "$installer"
            local status=$?
            rm -f "$installer"
            return "$status"
          }
          update_pi_pack() { as_agent nono pull nolabs-ai/pi; }
          update_omz() {
            as_agent zsh "$AGENT_HOME/.oh-my-zsh/tools/upgrade.sh" -v minimal
          }
          update_starship() {
            local installer
            installer="$(mktemp)" || return 1
            if ! curl --proto '=https' --tlsv1.2 -fsSL https://starship.rs/install.sh -o "$installer"; then
              rm -f "$installer"; return 1
            fi
            chmod 0700 "$installer"
            sh "$installer" -y -b /usr/local/bin
            local status=$?
            rm -f "$installer"
            return "$status"
          }
          step 'Ubuntu APT metadata' apt-get update
          step 'Ubuntu unattended upgrades' unattended-upgrade -v
          step 'Pi' update_pi
          step 'Herdr' update_herdr
          step 'nono' update_nono
          step 'nono Pi pack' update_pi_pack
          step 'Oh My Zsh' update_omz
          step 'Starship' update_starship
          log "Finished: failures=$failed"
          exit "$failed"

    - name: Create daily agentic maintenance service
      become_user: root
      ansible.builtin.copy:
        dest: /etc/systemd/system/agentic-update.service
        owner: root
        group: root
        mode: '0644'
        content: |
          [Unit]
          Description=Back up agent home and update Ubuntu and agentic tools
          Wants=network-online.target
          After=network-online.target
          [Service]
          Type=oneshot
          ExecStart=/usr/local/sbin/agentic-update
          TimeoutStartSec=2h
          Nice=10
          IOSchedulingClass=best-effort
          IOSchedulingPriority=7

    - name: Create daily maintenance timer
      become_user: root
      ansible.builtin.copy:
        dest: /etc/systemd/system/agentic-update.timer
        owner: root
        group: root
        mode: '0644'
        content: |
          [Unit]
          Description=Daily agent-home backup and Ubuntu/agentic updates
          [Timer]
          OnCalendar=*-*-* 04:00:00
          RandomizedDelaySec=30min
          Persistent=true
          Unit=agentic-update.service
          [Install]
          WantedBy=timers.target

    - name: Enable daily maintenance timer
      become_user: root
      ansible.builtin.systemd_service:
        name: agentic-update.timer
        enabled: true
        state: restarted
        daemon_reload: true

    # Conservative hardening: no modifications to root login or password authentication.
    # Opening the existing SSH ports *before* UFW activation prevents common lockouts.
    - name: Install host security packages
      become_user: root
      ansible.builtin.apt:
        name: [ufw, fail2ban, python3-systemd, apparmor, apparmor-utils]
        state: present

    - name: Configure fail2ban SSH jail using systemd journal
      become_user: root
      ansible.builtin.copy:
        dest: /etc/fail2ban/jail.d/90-agentic-ssh.local
        owner: root
        group: root
        mode: '0644'
        content: |
          [sshd]
          enabled = true
          backend = systemd
          banaction = ufw
          maxretry = 5
          findtime = 10m
          bantime = 1h
      register: agentic_fail2ban_config

    - name: Validate fail2ban configuration
      become_user: root
      ansible.builtin.command: fail2ban-client -t
      changed_when: false

    - name: Start and enable fail2ban
      become_user: root
      ansible.builtin.systemd_service:
        name: fail2ban
        enabled: true
        state: "{{ 'restarted' if agentic_fail2ban_config.changed else 'started' }}"

    - name: Apply conservative SSH daemon limits without changing login methods
      become_user: root
      ansible.builtin.copy:
        dest: /etc/ssh/sshd_config.d/90-agentic-hardening.conf
        owner: root
        group: root
        mode: '0644'
        content: |
          # Deliberately preserve PermitRootLogin and PasswordAuthentication.
          MaxAuthTries 5
          LoginGraceTime 30
          PermitEmptyPasswords no
      register: agentic_ssh_hardening

    - name: Validate SSH configuration before applying it
      become_user: root
      ansible.builtin.command: /usr/sbin/sshd -t
      changed_when: false

    - name: Reload SSH without dropping existing connections
      become_user: root
      ansible.builtin.systemd_service:
        name: ssh
        state: reloaded
      when: agentic_ssh_hardening.changed

    - name: Configure conservative kernel hardening
      become_user: root
      ansible.builtin.copy:
        dest: /etc/sysctl.d/90-agentic-hardening.conf
        owner: root
        group: root
        mode: '0644'
        content: |
          kernel.dmesg_restrict = 1
          kernel.kptr_restrict = 2
          fs.protected_hardlinks = 1
          fs.protected_symlinks = 1
          fs.protected_fifos = 2
          fs.protected_regular = 2
          net.ipv4.conf.all.accept_redirects = 0
          net.ipv4.conf.default.accept_redirects = 0
          net.ipv6.conf.all.accept_redirects = 0
          net.ipv6.conf.default.accept_redirects = 0
      register: agentic_sysctl_hardening

    - name: Confirm sysctl is available before loading kernel hardening
      become_user: root
      ansible.builtin.stat:
        path: /usr/sbin/sysctl
      register: agentic_sysctl_binary

    - name: Fail with actionable message if sysctl is missing
      ansible.builtin.assert:
        that: agentic_sysctl_binary.stat.exists
        fail_msg: "Missing /usr/sbin/sysctl: install the Ubuntu procps package."
      when: agentic_sysctl_hardening.changed

    - name: Load kernel hardening settings
      become_user: root
      ansible.builtin.command:
        argv:
          - /usr/sbin/sysctl
          - -p
          - /etc/sysctl.d/90-agentic-hardening.conf
      when: agentic_sysctl_hardening.changed

    - name: Enable AppArmor (when supported by this host)
      become_user: root
      ansible.builtin.systemd_service:
        name: apparmor
        enabled: true
        state: started
      failed_when: false

    - name: Detect SSH daemon listening ports for firewall exceptions
      become_user: root
      ansible.builtin.shell: |
        set -euo pipefail
        /usr/sbin/sshd -T | awk '$1=="port" && $2 ~ /^[0-9]+$/ {print $2}' | sort -un
      args: {executable: /bin/bash}
      register: ssh_listen_ports
      changed_when: false
      when: lookup('env', 'ENABLE_UFW') == 'true'

    - name: Refuse to enable UFW unless SSH ports can be detected
      ansible.builtin.assert:
        that:
          - ssh_listen_ports.stdout_lines | default([]) | length > 0
        fail_msg: 'Could not detect SSH listening ports; refusing firewall activation to prevent lockout.'
      when: lookup('env', 'ENABLE_UFW') == 'true'

    - name: Verify UFW executable is installed before changing firewall rules
      become_user: root
      ansible.builtin.stat:
        path: /usr/sbin/ufw
      register: agentic_ufw_binary
      when: lookup('env', 'ENABLE_UFW') == 'true'

    - name: Stop safely if UFW is missing
      ansible.builtin.assert:
        that: agentic_ufw_binary.stat.exists
        fail_msg: 'Missing /usr/sbin/ufw: install the Ubuntu ufw package before enabling the firewall.'
      when: lookup('env', 'ENABLE_UFW') == 'true'

    - name: Allow SSH ports before firewall activation
      become_user: root
      ansible.builtin.command: "/usr/sbin/ufw allow {{ item }}/tcp comment 'SSH - agentic bootstrap'"
      loop: "{{ ssh_listen_ports.stdout_lines | default([]) | unique }}"
      register: ufw_ssh_rules
      changed_when: "'Rules updated' in ufw_ssh_rules.stdout or 'Rules updated' in ufw_ssh_rules.stderr"
      when: lookup('env', 'ENABLE_UFW') == 'true'

    - name: Enable UFW with default incoming deny and outgoing allow
      become_user: root
      ansible.builtin.shell: |
        set -euo pipefail
        /usr/sbin/ufw default deny incoming
        /usr/sbin/ufw default allow outgoing
        /usr/sbin/ufw --force enable
      args: {executable: /bin/bash}
      register: ufw_enable_result
      changed_when: "'Firewall is active' in ufw_enable_result.stdout"
      when: lookup('env', 'ENABLE_UFW') == 'true'

    - name: Create shared read-only agentic status directory
      become_user: root
      ansible.builtin.file:
        path: /var/lib/agentic
        state: directory
        owner: root
        group: root
        mode: '0755'

    - name: Verify host security status directory exists
      become_user: root
      ansible.builtin.stat:
        path: /var/lib/agentic
      register: agentic_status_dir

    - name: Assert host security status directory exists
      become_user: root
      ansible.builtin.assert:
        that:
          - agentic_status_dir.stat.isdir | default(false)
        fail_msg: "Missing /var/lib/agentic: check bootstrap permissions and earlier directory task"

    - name: Write readable host security status for agent login screen
      become_user: root
      ansible.builtin.copy:
        dest: /var/lib/agentic/hardening-status
        owner: root
        group: root
        mode: '0644'
        content: |
          SSH protection: Fail2ban enabled
          SSH authentication: existing policy preserved
          UFW firewall: {{ 'managed and enabled' if lookup('env', 'ENABLE_UFW') == 'true' else 'not enabled by installer' }}
          AppArmor: managed by Ubuntu
          Kernel hardening: enabled

    # UFW status requires root. Publish a minimal read-only snapshot regularly,
    # instead of giving the interactive shell unrestricted sudo access.
    - name: Install firewall status snapshot helper
      become_user: root
      ansible.builtin.copy:
        dest: /usr/local/sbin/agentic-firewall-status
        owner: root
        group: root
        mode: '0755'
        content: |
          #!/usr/bin/env bash
          set -euo pipefail
          target=/var/lib/agentic/firewall-status
          install -d -o root -g root -m 0755 /var/lib/agentic
          temp="$(mktemp /var/lib/agentic/.firewall-status.XXXXXX)"
          trap 'rm -f "$temp"' EXIT
          chmod 0644 "$temp"
          status="$(LC_ALL=C /usr/sbin/ufw status 2>&1)" || {
            printf 'Unable to query firewall\n' > "$temp"
            mv -f "$temp" "$target"
            exit 1
          }
          if grep -q '^Status: inactive' <<< "$status"; then
            printf 'UFW inactive (no UFW filtering)\n' > "$temp"
          elif grep -q '^Status: active' <<< "$status"; then
            # List explicit inbound ALLOW rules, including ranges and IPv6.
            # This reports UFW policy rules, not listening sockets or provider firewalls.
            awk '/[[:space:]]ALLOW IN[[:space:]]/ {
              target=$1; protocol=$1; for (i=2; i<=NF; i++) {
                if ($i=="ALLOW" && $(i+1)=="IN") break
                target=target " " $i
              }
              print target
              found=1
            } END {if (!found) print "No inbound ALLOW rules"}' <<< "$status" > "$temp"
          else
            printf 'Unknown UFW status\n' > "$temp"
          fi
          mv -f "$temp" "$target"

    - name: Install firewall status refresh service
      become_user: root
      ansible.builtin.copy:
        dest: /etc/systemd/system/agentic-firewall-status.service
        owner: root
        group: root
        mode: '0644'
        content: |
          [Unit]
          Description=Publish read-only UFW inbound allow rules for the agentic login banner
          [Service]
          Type=oneshot
          ExecStart=/usr/local/sbin/agentic-firewall-status

    - name: Install firewall status refresh timer
      become_user: root
      ansible.builtin.copy:
        dest: /etc/systemd/system/agentic-firewall-status.timer
        owner: root
        group: root
        mode: '0644'
        content: |
          [Unit]
          Description=Refresh agentic firewall summary
          [Timer]
          OnBootSec=30s
          OnUnitActiveSec=2min
          Persistent=true
          Unit=agentic-firewall-status.service
          [Install]
          WantedBy=timers.target

    - name: Enable firewall status refresh timer
      become_user: root
      ansible.builtin.systemd_service:
        name: agentic-firewall-status.timer
        enabled: true
        state: restarted
        daemon_reload: true

    - name: Capture firewall status immediately
      become_user: root
      ansible.builtin.command: /usr/local/sbin/agentic-firewall-status
      changed_when: false

    - name: Verify binaries and profile
      ansible.builtin.shell: |
        set -e
        command -v node
        command -v pi
        command -v nono
        command -v herdr
        test -x "$HOME/.local/bin/nnpi"
        nono run --profile pi-herdr --dry-run -- /usr/bin/true >/dev/null
        herdr --version
        pi --version
      args: {executable: /bin/bash}
      changed_when: false
YAML

"${PRIV[@]}" env AGENT_USER="$AGENT_USER" SSH_SOURCE_USER="$SSH_SOURCE_USER" AUTO_REBOOT="$AUTO_REBOOT" REBOOT_TIME="$REBOOT_TIME" ENABLE_UFW="$ENABLE_UFW" ansible-playbook -i 'localhost,' "$playbook"
printf '\nProvisioning complete for %s.\n' "$AGENT_USER"
printf 'Switch accounts: su - %s\n' "$AGENT_USER"
printf 'Then run: nnpi (or use nnpi -p \"your prompt\")\n'
printf 'From your local Herdr client, connect via SSH as %s@<server>\n' "$AGENT_USER"
printf 'Ubuntu automatic upgrades: daily maintenance after a local backup (reboot=%s, time=%s)\n' "$AUTO_REBOOT" "$REBOOT_TIME"
printf 'OS and tooling updates: daily at 04:00 (+up to 30m jitter), via agentic-update.timer\n'
printf 'Agent home backups: /var/backups/agentic (root-only, last 14)\n'
printf 'Host security: Fail2ban, AppArmor, SSH limits, sysctl and UFW (enabled=%s)\n' "$ENABLE_UFW"
