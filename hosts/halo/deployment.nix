{ delib, ... }:
delib.host {
  name = "halo";
  nixos = {
    services.comin = {
      enable = true;
      exporter.listen_address = "127.0.0.1";
      remotes = [
        {
          name = "origin";
          url = "https://github.com/Valhallishe/infra.git";
          branches.main.name = "main";
        }
      ];
    };

  };
}
