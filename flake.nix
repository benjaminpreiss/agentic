{
  description = "Agentic provider-independent NixOS deployment";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    pi.url = "github:earendil-works/pi/stable";
    omp.url = "github:can1357/oh-my-pi";
    nono.url = "github:nolabs-ai/nono";
    herdr.url = "github:herdrdev/herdr";
    matt-skills = { url = "github:mattpocock/skills"; flake = false; };
  };
  outputs = inputs@{ nixpkgs, disko, ... }: {
    nixosConfigurations.agentic = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = [
        disko.nixosModules.disko
        ./modules/base.nix
        ./modules/disk.nix
        ./modules/agentic.nix
        ./modules/recovery.nix
        ./modules/firstboot.nix
        ./generated/machine.nix
        ({ lib, ... }: lib.mkIf (builtins.pathExists ./generated/facter.json) {
          hardware.facter.reportPath = ./generated/facter.json;
        })
      ];
    };
  };
}
