{
  delib,
  inputs,
  config,
  ...
}:
delib.host {
  name = "halo";
  myconfig.infra = {
    krozzzis.enable = true;
    web.enable = config.infra.hosts.halo.gateway.routes != [ ];
  };
  nixos = {
    imports = [ (inputs.import-tree ./_nixos) ];
    nixpkgs.hostPlatform = "x86_64-linux";
    system.stateVersion = "26.05";
    networking.hostName = "halo";
  };
}
