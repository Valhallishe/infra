{ delib, inputs, ... }:
delib.host {
  name = "vps";
  nixos = {
    imports = [ (inputs.import-tree ./_nixos) ];
    nixpkgs.hostPlatform = "x86_64-linux";
    system.stateVersion = "26.05";
    networking.hostName = "vps";
  };
}
