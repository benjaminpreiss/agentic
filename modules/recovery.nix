{ lib, ... }: {
  # The password hash is delivered via nixos-anywhere --extra-files.
  # The source is never imported into the Nix store or committed to Git.
  users.users.recovery = {
    isNormalUser = true;
    description = "Temporary local console recovery administrator";
    extraGroups = [ "wheel" ];
    hashedPasswordFile = "/etc/agentic/recovery-password-hash";
  };
  security.sudo.wheelNeedsPassword = true;
  # SSH remains key-only, including for the recovery account.
  services.openssh.settings.PasswordAuthentication = lib.mkForce false;
  services.openssh.settings.KbdInteractiveAuthentication = lib.mkForce false;
}
