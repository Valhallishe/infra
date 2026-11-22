{ config, ... }:
{
  infra.nodes.archserver.hostId = 2;

  infra.hosts.nixarchserver = {
    node = "archserver";
    publicGateway = "halo";
    services = {
      awg.peer = "halo";
      comin.branch = "main";

      authentik = {
        branding = "valhallishe";
        flows.http.port = 5680;
        httpsPort = 56443;
        dataDir = "/srv/docker/authentik";
        database.volume = "authentik_database";
        secretFile = ../../secrets/nixarchserver-authentik.age;
      };

      peertube = {
        branding = "valhallishe";
        flows.http.port = 9001;
        adminEmail = "admin@${config.infra.domain}";
        storage = "/media/disk/peertube";
        mount = {
          path = "/media/disk";
          unit = "media-disk.mount";
          uuid = "a1493909-cb3c-466f-9d4c-f7fae62d05ab";
        };
        secretFile = ../../secrets/nixarchserver-peertube.age;
      };

      # Inbuxa is applied separately using the configuration built by Nix.
      inbuxa = {
        branding = "valhallishe";
        dataDir = "/srv/docker/inbuxa";
        flows = {
          webmail.port = 18084;
          admin.port = 18081;
          scim.port = 18083;
        };
      };

      # Existing installations published through Halo.
      immich.flows.http.port = 2283;
      nextcloud = {
        branding = "valhallishe";
        flows.http.port = 6084;
      };
      vaultwarden.flows.http.port = 6082;
      minecraft.flows = {
        tcp = {
          protocol = "tcp";
          port = 25565;
          proxyProtocol = "v2";
        };
        udp = {
          protocol = "udp";
          port = 25565;
        };
      };
    };
  };
}
