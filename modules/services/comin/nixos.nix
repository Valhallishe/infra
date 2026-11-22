{
  delib,
  inputs,
  config,
  lib,
  ...
}:
let
  instance = config.infra.hosts.${config.networking.hostName}.services.comin or null;
in
delib.module {
  name = "infra.comin";
  nixos.always = {
    imports = [ inputs.comin.nixosModules.comin ];
    config.services.comin = lib.mkMerge [
      { enable = lib.mkDefault (instance != null); }
      (lib.mkIf (instance != null && config.services.comin.enable) {
        exporter.listen_address = "127.0.0.1";
        remotes = [
          {
            name = "origin";
            url = config.infra.repository;
            branches.main.name = instance.branch;
          }
        ];
      })
    ];
  };
}
