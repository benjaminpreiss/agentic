{ pkgs, lib, ... }:
let
  socketPath = "/run/agentic-github-mcp.sock";
  mcpEntry = builtins.toJSON {
    command = "${pkgs.socat}/bin/socat";
    args = [ "STDIO" "UNIX-CONNECT:${socketPath}" ];
    description = "GitHub repositories, issues, pull requests and CI via the official GitHub MCP server";
    exposure = "deferred";
  };
  configurePi = pkgs.writeShellApplication {
    name = "agentic-configure-github-mcp";
    runtimeInputs = [ pkgs.jq pkgs.coreutils ];
    text = ''
      set -euo pipefail
      config="$HOME/.pi/agent/mcp.json"
      mkdir -p "$(dirname "$config")"
      tmp="$(mktemp "$(dirname "$config")/.mcp.json.XXXXXXXX")"
      trap 'rm -f "$tmp"' EXIT
      if [ -e "$config" ]; then
        ${pkgs.jq}/bin/jq --argjson github '${mcpEntry}' \
          '.mcpServers = (.mcpServers // {}) | .mcpServers.github = $github' \
          "$config" > "$tmp"
      else
        ${pkgs.jq}/bin/jq -n --argjson github '${mcpEntry}' \
          '{mcpServers: {github: $github}}' > "$tmp"
      fi
      chmod 0600 "$tmp"
      mv -f "$tmp" "$config"
    '';
  };
in {
  # The listener is owned by systemd, not by Pi. Each accepted connection
  # spawns a dedicated official github-mcp-server stdio process.
  systemd.sockets.agentic-github-mcp = {
    description = "GitHub MCP local transport for agentic";
    wantedBy = [ "sockets.target" ];
    socketConfig = {
      ListenStream = socketPath;
      Accept = true;
      SocketUser = "agentic";
      SocketGroup = "users";
      SocketMode = "0600";
      RemoveOnStop = true;
    };
  };
  systemd.services."agentic-github-mcp@" = {
    description = "Official GitHub MCP server (per connection)";
    serviceConfig = {
      Type = "simple";
      DynamicUser = true;
      EnvironmentFile = "/etc/agentic/github-app/app.env";
      LoadCredential = "github-app.pem:/etc/agentic/github-app/private-key.pem";
      Environment = [ "GITHUB_APP_PRIVATE_KEY_PATH=%d/github-app.pem" ];
      ExecStart = "${pkgs.github-mcp-server}/bin/github-mcp-server stdio";
      StandardInput = "socket";
      StandardOutput = "inherit";
      StandardError = "journal";
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictSUIDSGID = true;
      LockPersonality = true;
      CapabilityBoundingSet = "";
      RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];
    };
  };
  # Merge only the github MCP entry; do not replace unrelated servers.
  # This runs as agentic so mcp.json stays writable by Pi.
  systemd.services.agentic-configure-github-mcp = {
    description = "Configure Pi built-in MCP for GitHub";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-tmpfiles-setup.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = "agentic";
      Group = "users";
      Environment = "HOME=/home/agentic";
      ExecStart = "${configurePi}/bin/agentic-configure-github-mcp";
    };
  };
}
