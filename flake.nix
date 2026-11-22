{
  description = "NixOS infrastructure for VPS and dedicated servers";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    # Autopush in 26.05 lacks Mozilla's fix for offline delivery with Redis (#1191).
    nixpkgs-autopush.url = "github:NixOS/nixpkgs/nixos-unstable";
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
      pkgs = nixpkgs.legacyPackages.${system};
      topology =
        (nixpkgs.lib.evalModules {
          specialArgs = { inherit inputs; };
          modules = [ ./infra.nix ];
        }).config.infra;
      endpoints = import ./lib/service-endpoints.nix {
        inherit (nixpkgs) lib;
        infra = topology;
      };
      nixarchserver = import ./hosts/nixarchserver/_build.nix {
        inherit pkgs topology endpoints;
        comin = inputs.comin.packages.${system}.comin;
      };
    in
    {
      nixosConfigurations =
        (denix.lib.configurations {
          inherit nixpkgs;
          home-manager = inputs.home-manager;
          moduleSystem = "nixos";
          useHomeManagerModule = false;
          extraModules = [
            (inputs.import-tree [
              ./hosts
              ./modules
            ])
          ];
          extensions = with denix.lib.extensions; [
            args
            (base.withConfig { args.enable = true; })
          ];
          specialArgs = { inherit inputs; };
        })
        // {
          # Comin's Linux flake executor expects this interface.
          nixarchserver.config = {
            system.build.toplevel = nixarchserver;
            services.comin.machineId = null;
          };
        };
      packages.x86_64-linux.nixarchserver = nixarchserver;
      packages.x86_64-linux.bootstrap-secrets = pkgs.writeShellApplication {
        name = "bootstrap-secrets";
        runtimeInputs = with pkgs; [
          age
          openssh
          python3
          wireguard-tools
        ];
        text = ''
          exec ${pkgs.python3}/bin/python3 ${./scripts/bootstrap-secrets.py} "$@"
        '';
      };
      apps.x86_64-linux.bootstrap-secrets = {
        type = "app";
        program = "${self.packages.x86_64-linux.bootstrap-secrets}/bin/bootstrap-secrets";
      };
      packages.x86_64-linux.inbuxa-config = import ./modules/services/inbuxa/_package.nix {
        inherit pkgs endpoints topology;
        hostname = "nixarchserver";
      };
      packages.x86_64-linux.service-themes = import ./modules/branding/_service-themes.nix {
        inherit pkgs;
        authentikProfile = topology.branding.${topology.hosts.nixarchserver.services.authentik.branding};
        inbuxaProfile = topology.branding.${topology.hosts.nixarchserver.services.inbuxa.branding};
        nextcloudProfile = topology.branding.${topology.hosts.nixarchserver.services.nextcloud.branding};
      };
      checks.x86_64-linux = {
        inherit nixarchserver;
        vps = self.nixosConfigurations.vps.config.system.build.toplevel;
        halo = self.nixosConfigurations.halo.config.system.build.toplevel;
      };
    };
}
