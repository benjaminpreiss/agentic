{
  description = "Agentic provider-independent NixOS deployment";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
  };
  outputs = { nixpkgs, disko, ... }: {
    nixosConfigurations.agentic = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        disko.nixosModules.disko
        ./modules/base.nix
        ./modules/disk.nix
        ./modules/agentic.nix
        ./generated/machine.nix
        # nixos-anywhere generates this during installation. The path is
        # absent during the initial flake evaluation and added afterwards.
        ({ lib, ... }: lib.mkIf (builtins.pathExists ./generated/facter.json) {
          hardware.facter.reportPath = ./generated/facter.json;
        })
      ];
    };
  };
}
