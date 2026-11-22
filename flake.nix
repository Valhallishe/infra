{
  description = "NixOS infrastructure for VPS and dedicated servers";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    import-tree.url = "github:vic/import-tree";
    denix.url = "github:yunfachi/denix";
    denix.inputs.home-manager.follows = "home-manager";
    home-manager.url = "github:nix-community/home-manager/master";
    disko.url = "github:nix-community/disko";
    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";
    stylix.url = "github:nix-community/stylix/release-26.05";
    stylix.inputs.nixpkgs.follows = "nixpkgs";
    comin.url = "github:nlewo/comin";
    comin.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      denix,
      ...
    }@inputs:
    let
      system = "x86_64-linux";
      nixarchserver = import ./hosts/nixarchserver {
        pkgs = nixpkgs.legacyPackages.${system};
        comin = inputs.comin.packages.${system}.comin;
      };
    in
    {
      nixosConfigurations = (denix.lib.configurations {
        inherit nixpkgs;
        home-manager = inputs.home-manager;
        moduleSystem = "nixos";
        paths = [
          ./lib/declarations
          ./modules
          ./hosts/halo
          ./hosts/vps
        ];
        extensions = with denix.lib.extensions; [
          args
          (base.withConfig { args.enable = true; })
        ];
        specialArgs = { inherit inputs; };
      }) // {
        # Comin's Linux flake executor expects this interface.
        nixarchserver.config = {
          system.build.toplevel = nixarchserver;
          services.comin.machineId = null;
        };
      };
      packages.x86_64-linux.nixarchserver = nixarchserver;
      packages.x86_64-linux.service-themes = self.nixosConfigurations.halo.config.infra.serviceThemes;
      checks.x86_64-linux = {
        inherit nixarchserver;
        vps = self.nixosConfigurations.vps.config.system.build.toplevel;
        halo = self.nixosConfigurations.halo.config.system.build.toplevel;
      };
    };
}
