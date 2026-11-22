{ delib, inputs, ... }:
delib.module {
  name = "infra.disko";
  nixos.always.imports = [ inputs.disko.nixosModules.disko ];
}
