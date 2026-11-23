{
  config,
  inputs,
  lib,
  ...
}:
let
  inherit (config.infra) fileStorage;
  inherit (config.infra.hosts.nixarchserver) services;
  systemdUtils = import (inputs.nixpkgs + "/nixos/lib/utils.nix") {
    inherit lib config;
    pkgs = null;
  };
  fileMount = {
    path = fileStorage;
    unit = "${systemdUtils.escapeSystemdPath fileStorage}.mount";
    uuid = "a1493909-cb3c-466f-9d4c-f7fae62d05ab";
  };
  onDisk = location: {
    inherit location;
    mount = fileMount;
  };
  dockerVolume = location: {
    kind = "dockerVolume";
    inherit location;
  };
in
{
  infra.nodes.archserver.hostId = 2;

  infra.hosts.nixarchserver = {
    node = "archserver";
    publicGateway = "halo";
    services = {
      awg.peer = "halo";
      comin = {
        branch = "main";
        storage.state.location = "/var/lib/comin";
      };

      authentik = {
        overlayAddress = "10.1.2.2";
        branding = "valhallishe";
        flows.http.port = 5680;
        httpsPort = 56443;
        storage = {
          project.location = "/srv/docker/authentik";
          data.location = "${services.authentik.storage.project.location}/data";
          templates.location = "${services.authentik.storage.project.location}/custom-templates";
          certificates.location = "${services.authentik.storage.project.location}/certs";
          database = dockerVolume "authentik_database";
        };
        secretFile = ../../secrets/nixarchserver-authentik.age;
      };

      peertube = {
        overlayAddress = "10.1.2.3";
        branding = "valhallishe";
        flows.http.port = 80;
        flows.http.overlay = true;
        adminEmail = "admin@${config.infra.domain}";
        storage = {
          files = onDisk "${fileStorage}/peertube-podman";
          config.location = "${config.infra.systemStorage}/peertube/config";
          database.location = "${config.infra.systemStorage}/peertube/postgres";
          redis.location = "${config.infra.systemStorage}/peertube/redis";
        };
        secretFile = ../../secrets/nixarchserver-peertube.age;
      };

      inbuxa = {
        overlayAddress = "10.1.2.4";
        branding = "valhallishe";
        storage = {
          project.location = "/srv/docker/inbuxa";
          config.location = "${services.inbuxa.storage.project.location}/config";
          mail.location = "${services.inbuxa.storage.project.location}/data";
        };
        flows = {
          webmail.port = 18084;
          admin.port = 18081;
          scim.port = 18083;
        };
      };

      opencloud = {
        overlayAddress = "10.1.2.5";
        apps = {
          model3d = true;
          unzip = true;
          epubReader = true;
          pdfViewer = true;
        };
        branding = "valhallishe";
        flows.http.port = 80;
        flows.http.overlay = true;
        storage = {
          data.location = "${config.infra.systemStorage}/opencloud/data";
          files = onDisk "${fileStorage}/opencloud/data/storage/users";
          radicale.location = "${config.infra.systemStorage}/opencloud/radicale";
        };
      };

      vaultwarden = {
        overlayAddress = "10.1.2.6";
        flows.http.port = 80;
        flows.http.overlay = true;
        image = "docker.io/vaultwarden/server@sha256:4fe17f415f90087377d37c755e0ea3cf189dcc6794e49cdd2a9adbb4937d9e1f";
        storage.data.location = "${config.infra.systemStorage}/vaultwarden/data";
        secretFile = ../../secrets/nixarchserver-vaultwarden.age;
      };

      immich = {
        overlayAddress = "10.1.2.7";
        flows.http.port = 80;
        flows.http.overlay = true;
        storage = {
          project.location = "/srv/docker/immich";
          library = onDisk "${fileStorage}/immich";
          database.location = "${config.infra.systemStorage}/immich/postgres";
          modelCache.location = "${config.infra.systemStorage}/immich/model-cache";
          redis.location = "${config.infra.systemStorage}/immich/redis";
        };
        secretFile = ../../secrets/nixarchserver-immich.age;
      };
      # Existing installations published through Halo.
      nextcloud = {
        branding = "valhallishe";
        flows.http.port = 6084;
        storage = {
          data.kind = "external";
          database.kind = "external";
        };
      };
      minecraft = {
        overlayAddress = "10.1.2.8";
        storage.worlds.kind = "external";
        flows = {
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
  };
}
