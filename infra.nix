{ inputs, ... }:
{
  imports = [
    ./lib/topology.nix
    ./modules/branding/_profile.nix
    (inputs.import-tree.initFilter (path: builtins.baseNameOf path == "_inventory.nix") ./hosts)
  ];

  infra = {
    network.subnet = "10.1.0.0/16";
    domain = "valhallishe.net";
    repository = "https://github.com/Valhallishe/infra.git";
  };
}
