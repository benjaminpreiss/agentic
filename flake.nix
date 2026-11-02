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
    themoss.url = "github:benjaminpreiss/themoss.net/05f25bf2e700deb55c59882d00e781a1e1583d07";
  };
  outputs = inputs@{ nixpkgs, disko, ... }: {
    toolkitPath = inputs.themoss.outPath;
    nixosConfigurations.agentic = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = [
        disko.nixosModules.disko
        inputs.themoss.nixosModules.update
        ({ ... }: {
          services.themossUpdate = {
            enable = true;
            repository = "/var/lib/agentic/source";
            machine = "/var/lib/agentic/machine";
            host = "agentic";
            state = "/var/lib/agentic/deployment";
          };
        })
        ./nixos/modules/base.nix
        ./nixos/modules/disk.nix
        ./deployment/modules/agentic.nix
        ./nixos/modules/recovery.nix
        ./nixos/modules/firstboot.nix
        ./generated/machine.nix
        ({ lib, ... }: lib.mkIf (builtins.pathExists ./generated/facter.json) {
          hardware.facter.reportPath = ./generated/facter.json;
        })
      ];
    };
  };
}
