{ delib, ... }:
delib.module {
  name = "infra";
  nixos.always.imports = [ ../infra.nix ];
}
