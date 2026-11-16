{ delib, config, ... }:
delib.module {
  name = "infra.web";
  options.infra.web.enable = delib.boolOption false;
  nixos.ifEnabled = {
    assertions = [
      {
        assertion = config.networking.domain != null;
        message = "infra.web requires networking.domain to be set.";
      }
    ];
    services.caddy = {
      enable = true;
      openFirewall = true;
      virtualHosts."${config.networking.domain}".extraConfig = ''
        respond "" 200
      '';
    };
  };
}
