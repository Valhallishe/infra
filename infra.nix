{
  imports = [
    ./lib/topology.nix
    ./modules/branding
    ./nodes/archserver.nix
    ./nodes/halo.nix
    ./hosts/halo
    ./hosts/nixarchserver
  ];

  infra = {
    network.subnet = "10.1.0.0/16";
    domain = "valhallishe.net";
    repository = "https://github.com/Valhallishe/infra.git";
  };
}
