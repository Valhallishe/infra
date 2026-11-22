{
  delib,
  inputs,
  config,
  ...
}:
delib.host {
  name = "halo";
  useHomeManagerModule = false;
  myconfig.infra.krozzzis.enable = true;
  nixos = {
    imports = [
      inputs.disko.nixosModules.disko
      inputs.comin.nixosModules.comin
      inputs.agenix.nixosModules.default
      inputs.stylix.nixosModules.stylix
    ];
    nixpkgs.hostPlatform = "x86_64-linux";
    system.stateVersion = "26.05";
    networking.hostName = "halo";
  };
}
