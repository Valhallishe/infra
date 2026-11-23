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
        branding = "valhallishe";
        flows.http.port = 9001;
        adminEmail = "admin@${config.infra.domain}";
        storage = {
          files = onDisk "${fileStorage}/peertube";
          config = dockerVolume "nixarchserver-peertube_config";
          database = dockerVolume "nixarchserver-peertube_postgres";
          redis = dockerVolume "nixarchserver-peertube_redis";
        };
        secretFile = ../../secrets/nixarchserver-peertube.age;
      };

      # Inbuxa is applied separately using the configuration built by Nix.
      inbuxa = {
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
        apps = {
          model3d = true;
          unzip = true;
          epubReader = true;
          pdfViewer = true;
        };
        branding = "valhallishe";
        flows.http.port = 9200;
        storage = {
          data = onDisk "${fileStorage}/opencloud/data";
          config = onDisk "${fileStorage}/opencloud/config";
          files = {
            location = "${services.opencloud.storage.data.location}/storage/users";
            inherit (services.opencloud.storage.data) mount;
          };
          radicale = onDisk "${fileStorage}/radicale";
        };
      };

      vaultwarden = {
        flows.http.port = 6082;
        image = "vaultwarden/server@sha256:4fe17f415f90087377d37c755e0ea3cf189dcc6794e49cdd2a9adbb4937d9e1f";
        storage.data.location = "/srv/docker/vaultwarden/vw-data";
        secretFile = ../../secrets/nixarchserver-vaultwarden.age;
      };

      # Existing installations published through Halo.
      immich = {
        flows.http.port = 2283;
        storage = {
          library.kind = "external";
          database.kind = "external";
        };
      };
      nextcloud = {
        branding = "valhallishe";
        flows.http.port = 6084;
        storage = {
          data.kind = "external";
          database.kind = "external";
        };
      };
      minecraft = {
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
