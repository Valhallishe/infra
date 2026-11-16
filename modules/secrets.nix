{ delib, inputs, ... }:
delib.module {
  name = "infra.secrets";
  nixos.always.imports = [ inputs.agenix.nixosModules.default ];
}
