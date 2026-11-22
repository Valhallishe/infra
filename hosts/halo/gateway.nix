{ delib, config, ... }:
let
  domain = config.infra.domain;
in
delib.host {
  name = "halo";
  myconfig.infra.web.enable = true;
  nixos.infra.web.routes = [
    {
      service = "authentik";
      inbound = "web";
      outbound = "web";
      domain = "sso.${domain}";
    }
    {
      service = "immich";
      inbound = "web";
      outbound = "web";
      domain = "photos.${domain}";
    }
    {
      service = "nextcloud";
      inbound = "web";
      outbound = "web";
      domain = "files.${domain}";
    }
    {
      service = "vaultwarden";
      inbound = "web";
      outbound = "web";
      domain = "pass.${domain}";
    }
    {
      service = "inbuxa";
      inbound = "webmail";
      outbound = "webmail";
      domain = "mail.${domain}";
    }
    {
      service = "inbuxa";
      inbound = "admin";
      outbound = "admin";
      domain = "admin.mail.${domain}";
    }
    {
      service = "minecraft";
      inbound = "tcp";
      outbound = "tcp";
      domain = "mc.play.${domain}";
    }
    {
      service = "minecraft";
      inbound = "udp";
      outbound = "udp";
      domain = "mc.play.${domain}";
    }
  ];
}
