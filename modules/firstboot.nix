{ pkgs, config, ... }: {
  systemd.services.agentic-firstboot-check = {
    description = "Inspect first boot network and SSH availability";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-networkd.service" "sshd.service" ];
    serviceConfig.Type = "oneshot";
    path = with pkgs; [ iproute2 systemd coreutils gnugrep ];
    script = ''
      {
        echo "===== AGENTIC FIRST BOOT DIAGNOSTICS ====="
        date -Is
        ip -br link || true
        ip -br addr || true
        ip -4 route || true
        networkctl list --no-pager || true
        systemctl is-active systemd-networkd.service || true
        systemctl is-active sshd.service || true
        echo "===== END AGENTIC DIAGNOSTICS ====="
      } > /dev/console 2>&1
    '';
  };
}
