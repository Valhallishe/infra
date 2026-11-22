{ config, ... }:
let
  toArch = subdomain: service: flow: {
    domain = "${subdomain}.${config.infra.domain}";
    to = {
      host = "nixarchserver";
      inherit service flow;
    };
  };
in
{
  infra.nodes.halo = {
    hostId = 1;
    awg.endpoint = "net.${config.infra.domain}:${toString config.infra.network.port}";
  };

  infra.hosts.halo = {
    node = "halo";
    branding = "valhallishe";
    services = {
      awg.peer = "archserver";
      comin.branch = "main";
      inbuxaRelay.linkPort = 10443;
      autopush.flows = {
        connect.port = 8280;
        endpoint.port = 8282;
      };
    };
    gateway.routes = [
      (toArch "sso" "authentik" "http")
      (toArch "videos" "peertube" "http")
      (toArch "photos" "immich" "http")
      (toArch "files" "opencloud" "http")
      (toArch "pass" "vaultwarden" "http")
      (toArch "mail" "inbuxa" "webmail")
      (toArch "admin.mail" "inbuxa" "admin")
      (toArch "mc.play" "minecraft" "tcp")
      (toArch "mc.play" "minecraft" "udp")
      {
        domain = "push.${config.infra.domain}";
        to = {
          host = "halo";
          service = "autopush";
          flow = "connect";
        };
      }
      {
        domain = "push.${config.infra.domain}";
        pathPrefixes = [
          "/wpush/"
          "/m/"
        ];
        to = {
          host = "halo";
          service = "autopush";
          flow = "endpoint";
        };
      }
    ];
  };
}
