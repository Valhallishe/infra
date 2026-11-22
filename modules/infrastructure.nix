{ delib, inputs, ... }:
delib.module {
  name = "infra";
  nixos.always.imports = [
    (inputs.import-tree (inputs.self + "/lib/nixos"))
    (inputs.self + "/infra.nix")
  ];
}
