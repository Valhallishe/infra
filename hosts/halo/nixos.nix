{
  delib,
  inputs,
  config,
  ...
}:
let
  host = config.infra.hosts.halo;
in
delib.host {
  name = "halo";
  useHomeManagerModule = false;
  myconfig.infra = {
    krozzzis.enable = true;
    web.enable = host.gateway.routes != [ ];
  };
  nixos = {
    infra.awg = {
      enable = host.services.awg != null;
      peers = if host.services.awg == null then [ ] else [ host.services.awg.peer ];
    };
    services.comin.enable = host.services.comin != null;
    imports = [
      ../../modules/services/inbuxa/relay.nix
      ../../modules/services/comin/nixos.nix
      ../../modules/branding/nixos.nix
      inputs.disko.nixosModules.disko
      inputs.comin.nixosModules.comin
      inputs.agenix.nixosModules.default
    ];
    nixpkgs.hostPlatform = "x86_64-linux";
    system.stateVersion = "26.05";
    networking.hostName = "halo";
  };
}
