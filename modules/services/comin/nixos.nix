{ config, lib, ... }:
{
  config = lib.mkIf config.services.comin.enable {
    services.comin = {
      exporter.listen_address = "127.0.0.1";
      remotes = [
        {
          name = "origin";
          url = config.infra.repository;
          branches.main.name = config.infra.hosts.${config.networking.hostName}.services.comin.branch;
        }
      ];
    };
  };
}
