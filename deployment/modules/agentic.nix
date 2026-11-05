{ config, pkgs, lib, inputs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  piPkg = inputs.pi.packages.${system}.default;
  ompPkg = inputs.omp.packages.${system}.default;
  nonoPkg = inputs.nono.packages.${system}.prebuilt;
  herdrPkg = inputs.herdr.packages.${system}.default;
  skillsSource = ../../skills/available;
  enabledSkills = import ../../skills/select.nix;
  # Paths are relative to skills/available; reject traversal at evaluation time.
  checkedSkills = lib.mapAttrsToList (name: relative:
    assert builtins.match "[a-zA-Z0-9_/-]+" name != null;
    assert builtins.match "[a-zA-Z0-9_/-]+" relative != null;
    assert !(lib.hasInfix ".." relative) && !(lib.hasPrefix "/" relative);
    assert builtins.pathExists (skillsSource + "/${relative}/SKILL.md");
    { inherit name relative; }) enabledSkills;
  sandboxedPi = pkgs.writeShellApplication {
    name = "pi";
    runtimeInputs = [ pkgs.coreutils nonoPkg herdrPkg ];
    text = lib.replaceStrings [ "@NONO@" "@PI@" ] [ "${nonoPkg}" "${piPkg}" ]
      (builtins.readFile ../scripts/pi.sh);
  };
  sandboxedOmp = pkgs.writeShellApplication {
    name = "omp";
    runtimeInputs = [ pkgs.coreutils nonoPkg ];
    text = lib.replaceStrings [ "@NONO@" "@OMP@" ] [ "${nonoPkg}" "${ompPkg}" ]
      (builtins.readFile ../scripts/omp.sh);
  };
  tcpPorts = config.networking.firewall.allowedTCPPorts;
  udpPorts = config.networking.firewall.allowedUDPPorts;
  formatPorts = ports: if ports == [] then "none" else lib.concatStringsSep ", " (map toString ports);
  auditReport = pkgs.writeShellScriptBin "agentic-github-protection-report" ''
    report=/var/lib/agentic-github-protection/report
    if [ ! -r "$report" ]; then
      echo 'No readable GitHub protection audit report yet.' >&2
      exit 1
    fi
    ${pkgs.coreutils}/bin/cat -- "$report"
  '';
  status = pkgs.writeShellScriptBin "agentic-status" (lib.replaceStrings
    [ "@SYSTEMD@" "@GAWK@" "@COREUTILS@" "@FIREWALL@" "@TCP_PORTS@" "@UDP_PORTS@" ]
    [ "${pkgs.systemd}" "${pkgs.gawk}" "${pkgs.coreutils}"
      (if config.networking.firewall.enable then "yes" else "no")
      (formatPorts tcpPorts) (formatPorts udpPorts) ]
    (builtins.readFile ../scripts/status.sh));
  backup = pkgs.writeShellApplication {
    name = "agentic-backup";
    runtimeInputs = with pkgs; [ coreutils gnutar gzip findutils ];
    text = builtins.readFile ../scripts/backup.sh;
  };

in {
  imports = [ ./github-mcp.nix ];
  # Do not expose the raw agent packages on the system PATH: command discovery
  # must find the sandbox launchers, not an unsandboxed binary.
  environment.systemPackages = [ sandboxedPi sandboxedOmp status auditReport backup pkgs.ghostty.terminfo nonoPkg herdrPkg ];

  # Activation installs the currently selected skills as links to the staged,
  # versioned source and updates links from previous generations. It manages
  # only skills/agentic; the old skills/mattpocock link is an operator cleanup
  # step (see docs/upgrades/PR-28-ACTION-REQUIRED.md), not an activation side effect.
  systemd.services.agentic-skills = {
    description = "Install global Pi skills and agentic nono profiles";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" ];
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
    path = [ pkgs.coreutils ];
    script = lib.replaceStrings [ "@SKILL_LINKS@" "@PI_PROFILE@" "@OMP_PROFILE@" ] [
      (lib.concatMapStringsSep "\n" ({ name, relative }: ''
        if [ ! -e "$managed/${name}" ] && [ ! -L "$managed/${name}" ]; then
          ln -s ${skillsSource}/${relative} "$managed/${name}"
          chown -h agentic:users "$managed/${name}"
        fi
      '') checkedSkills)
      "${../../nixos/profiles/pi-herdr.json}" "${../../nixos/profiles/omp-agentic.json}"
    ] (builtins.readFile ../scripts/install-skills.sh);
  };
  # Automatic update checks, rather than unreviewed live configuration swaps.
  # Flake inputs are upgraded deliberately from the deployment host.
  nix.gc = { automatic = true; dates = "weekly"; options = "--delete-older-than 30d"; };
  nix.optimise.automatic = true;
  system.autoUpgrade.enable = false;
  systemd.tmpfiles.rules = [
    "d /home/agentic/work 0750 agentic users - -"
    "d /home/agentic/.pi 0755 agentic users - -"
    "d /home/agentic/.pi/agent 0755 agentic users - -"
    "z /home/agentic/.pi 0755 agentic users - -"
    "z /home/agentic/.pi/agent 0755 agentic users - -"
    "d /home/agentic/.config 0755 agentic users - -"
    "d /home/agentic/.config/nono 0755 agentic users - -"
    "d /home/agentic/.config/nono/profiles 0700 agentic users - -"
    "d /home/agentic/.config/nono/packages 0700 agentic users - -"
    "d /home/agentic/.config/nono/profile-drafts 0700 agentic users - -"
    "d /var/backups/agentic 0700 root root - -"
  ];
  # Prevent zsh-newuser-install. This creates the startup file only if absent;
  # the global interactive configuration below remains declarative.
  system.userActivationScripts.agenticZshrc = ''
    if [ -d /home/agentic ]; then
      if [ ! -e /home/agentic/.zshrc ]; then
        touch /home/agentic/.zshrc
        chown agentic:users /home/agentic/.zshrc
        chmod 0644 /home/agentic/.zshrc
      fi
    fi
  '';
  programs.zsh.promptInit = lib.mkForce ''
    eval "$(${pkgs.starship}/bin/starship init zsh)"
  '';
  programs.zsh.interactiveShellInit = ''
    # Agent launchers take precedence even if a user installed raw binaries
    # under ~/.local/bin. Other user tools remain available there.
    export PATH="${sandboxedPi}/bin:${sandboxedOmp}/bin:$HOME/.local/bin:$PATH"
    # Existing systems may lack the Ghostty definition. Keep a safe fallback.
    if [[ "$TERM" == xterm-ghostty ]] && ! ${pkgs.ncurses}/bin/infocmp xterm-ghostty >/dev/null 2>&1; then
      export TERM=xterm-256color
    fi
    if [[ "$(id -un)" == agentic && -z "''${AGENTIC_WELCOME_SHOWN:-}" && -z "''${AGENTIC_NO_WELCOME:-}" ]]; then
      export AGENTIC_WELCOME_SHOWN=1
      ${status}/bin/agentic-status
    fi
  '';
  systemd.services.agentic-backup = {
    description = "Back up agentic home directory locally";
    serviceConfig = { Type = "oneshot"; ExecStart = "${backup}/bin/agentic-backup"; User = "root"; };
  };
  systemd.timers.agentic-backup = {
    wantedBy = [ "timers.target" ];
    timerConfig = { OnCalendar = "*-*-* 03:30:00"; RandomizedDelaySec = "20min"; Persistent = true; };
  };
}
