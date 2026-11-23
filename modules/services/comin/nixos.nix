{
  delib,
  inputs,
  config,
  lib,
  ...
}:
let
  defaultStateDir = "/var/lib/comin";
  instance = config.infra.hosts.${config.networking.hostName}.services.comin or null;
in
delib.module {
  name = "infra.comin";
  nixos.always = {
    imports = [ inputs.comin.nixosModules.comin ];
    config = {
      services.comin = lib.mkMerge [
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
      systemd.services.comin =
        lib.mkIf
          (
            instance != null
            && config.services.comin.enable
            && instance.storage.state.location != defaultStateDir
          )
          {
            unitConfig.RequiresMountsFor = instance.storage.state.location;
            serviceConfig.BindPaths = [ "${instance.storage.state.location}:${defaultStateDir}" ];
          };
    };
  };
}
