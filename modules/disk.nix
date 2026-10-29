{ config, lib, ... }:
let cfg = config.agenticMachine;
in {
  options.agenticMachine = {
    disk = lib.mkOption { type = lib.types.str; description = "Whole disk erased by Disko"; };
    bootMode = lib.mkOption { type = lib.types.enum [ "uefi" "bios" ]; };
  };
  config = {
    disko.devices.disk.main = {
      type = "disk";
      device = cfg.disk;
      content = {
        type = "gpt";
        partitions =
          (lib.optionalAttrs (cfg.bootMode == "bios") {
            bios = { priority = 1; size = "2M"; type = "EF02"; };
          }) // (lib.optionalAttrs (cfg.bootMode == "uefi") {
            ESP = {
              priority = 1;
              size = "1G";
              type = "EF00";
              content = {
                type = "filesystem"; format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
          }) // {
            root = {
              priority = 3; size = "100%";
              content = { type = "filesystem"; format = "ext4"; mountpoint = "/"; };
            };
          };
      };
    };
    boot.loader = lib.mkMerge [
      (lib.mkIf (cfg.bootMode == "uefi") {
        systemd-boot.enable = true;
        efi.canTouchEfiVariables = true;
      })
      (lib.mkIf (cfg.bootMode == "bios") {
        grub.enable = true;
        grub.device = cfg.disk;
        grub.efiSupport = false;
      })
    ];
  };
}
