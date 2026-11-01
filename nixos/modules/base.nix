{ config, lib, pkgs, ... }:
let cfg = config.agenticMachine; in {
  options.agenticMachine = {
    hostname = lib.mkOption { type = lib.types.str; };
    sshKey = lib.mkOption { type = lib.types.str; };
    sshPort = lib.mkOption { type = lib.types.port; default = 22; };
    networkMode = lib.mkOption { type = lib.types.enum [ "dhcp" "static" ]; default = "dhcp"; };
    networkInterface = lib.mkOption { type = lib.types.str; default = ""; };
    networkMAC = lib.mkOption { type = lib.types.str; default = ""; };
    staticIPv4 = lib.mkOption { type = lib.types.str; default = ""; };
    gatewayIPv4 = lib.mkOption { type = lib.types.str; default = ""; };
    dnsServers = lib.mkOption { type = lib.types.listOf lib.types.str; default = []; };
  };
  config = {
    system.stateVersion = "26.05";
    nix.settings.experimental-features = [ "nix-command" "flakes" ];
    networking.hostName = cfg.hostname;
    networking.useNetworkd = true;
    systemd.network.enable = true;
    # Only one usable interface needs to be online. Secondary interfaces may
    # have carrier but no DHCP lease, and must not block service activation.
    systemd.network.wait-online.anyInterface = true;
    networking.useDHCP = false;
    assertions = [{ assertion = cfg.networkMAC != ""; message = "A confirmed network interface MAC address is required"; }];
    systemd.network.networks."10-agentic" = {
      matchConfig.MACAddress = cfg.networkMAC;
      addresses = lib.optionals (cfg.networkMode == "static") [ { Address = cfg.staticIPv4; } ];
      routes = lib.optionals (cfg.networkMode == "static") [ { Gateway = cfg.gatewayIPv4; } ];
      networkConfig.DHCP = if cfg.networkMode == "dhcp" then "ipv4" else "no";
      dns = lib.optionals (cfg.networkMode == "static") cfg.dnsServers;
    };
    time.timeZone = "UTC";
    users.mutableUsers = false;
    users.users.root.openssh.authorizedKeys.keys = [ cfg.sshKey ];
    users.users.agentic = {
      isNormalUser = true;
      home = "/home/agentic";
      createHome = true;
      shell = pkgs.zsh;
      openssh.authorizedKeys.keys = [ cfg.sshKey ];
      extraGroups = []; # no sudo / wheel
    };
    services.openssh = {
      enable = true;
      ports = [ cfg.sshPort ];
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "prohibit-password";
        X11Forwarding = false;
        MaxAuthTries = 5;
      };
    };
    services.fail2ban.enable = true;
    security.apparmor.enable = true;
    networking.firewall = {
      enable = true;
      allowedTCPPorts = [ cfg.sshPort ];
    };
    boot.kernel.sysctl = {
      "kernel.dmesg_restrict" = 1;
      "kernel.kptr_restrict" = 2;
      "fs.protected_hardlinks" = 1;
      "fs.protected_symlinks" = 1;
      "net.ipv4.conf.all.accept_redirects" = 0;
      "net.ipv4.conf.default.accept_redirects" = 0;
    };
    environment.systemPackages = with pkgs; [ git curl wget jq openssl gnupg tmux vim zsh starship nodejs_24 python3 ncurses ];
    programs.zsh.enable = true;
    programs.starship.enable = true;
    programs.zsh.enableCompletion = true;
    programs.zsh.autosuggestions.enable = true;
    programs.zsh.syntaxHighlighting.enable = true;
    # OS updates must be explicitly deployed from a locked flake.
    # Automatic NixOS rebuilds are intentionally not enabled until
    # an immutable, machine-specific configuration source is installed.

  };
}
