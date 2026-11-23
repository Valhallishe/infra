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
      comin = {
        branch = "main";
        storage.state.location = "/var/lib/comin";
      };
      inbuxaRelay = {
        overlayAddress = "10.1.1.2";
        linkPort = 10443;
        storage.state.location = "/var/lib/inbuxa-relay";
      };
      autopush = {
        overlayAddress = "10.1.1.3";
        flows = {
          connect.port = 8280;
          endpoint.port = 8282;
        };
        storage = {
          keys.location = "/var/lib/autopush";
          redis.location = "/var/lib/redis-autopush";
        };
      };
    };
    gateway.routes = [
      (toArch "sso" "authentik" "http")
      (toArch "account" "vpn-portal" "http")
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
