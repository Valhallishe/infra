{ pkgs, decrypt }:
let
  storage = "/media/disk/peertube";
  compose = pkgs.writeText "peertube-compose.json" (builtins.toJSON {
    services = {
      peertube = {
        image = "chocobozzz/peertube:v8.3.2";
        ports = [ "10.1.0.2:9001:9000" ];
        volumes = [ "${storage}:/data" "config:/config" ];
        environment = {
          PEERTUBE_DB_HOSTNAME = "postgres";
          PEERTUBE_DB_NAME = "peertube";
          PEERTUBE_DB_USERNAME = "peertube";
          PEERTUBE_DB_PASSWORD = "\${POSTGRES_PASSWORD:?}";
          PEERTUBE_REDIS_HOSTNAME = "redis";
          PEERTUBE_WEBSERVER_HOSTNAME = "videos.valhallishe.net";
          PEERTUBE_WEBSERVER_HTTPS = "true";
          PEERTUBE_TRUST_PROXY = ''["loopback","10.1.0.1"]'';
          PEERTUBE_SECRET = "\${PEERTUBE_SECRET:?}";
          PEERTUBE_ADMIN_EMAIL = "admin@valhallishe.net";
          PEERTUBE_INSTANCE_NAME = "Valhallishe Videos";
          PEERTUBE_INSTANCE_SHORT_DESCRIPTION = "Видеоплатформа Valhallishe";
          PEERTUBE_INSTANCE_CUSTOMIZATIONS_CSS = "\${PEERTUBE_BRAND_CSS:?}";
        };
        depends_on.postgres.condition = "service_healthy";
        depends_on.redis.condition = "service_started";
        restart = "on-failure";
      };
      postgres = {
        image = "postgres:17.6";
        environment = {
          POSTGRES_USER = "peertube";
          POSTGRES_DB = "peertube";
          POSTGRES_PASSWORD = "\${POSTGRES_PASSWORD:?}";
        };
        volumes = [ "postgres:/var/lib/postgresql/data" ];
        healthcheck = {
          test = [ "CMD" "pg_isready" "-U" "peertube" "-d" "peertube" ];
          interval = "3s";
          retries = 20;
        };
        restart = "on-failure";
      };
      redis = {
        image = "redis:8-alpine";
        volumes = [ "redis:/data" ];
        restart = "on-failure";
      };
    };
    volumes = { config = {}; postgres = {}; redis = {}; };
  });
  run = pkgs.writeShellScript "peertube-compose" ''
    set -euo pipefail
    export PATH=/usr/bin
    umask 077
    if [[ $1 == up ]]; then
      test "$(findmnt -n -o UUID --mountpoint /media/disk)" = a1493909-cb3c-466f-9d4c-f7fae62d05ab
      mkdir -p ${storage}
      ${decrypt ../../secrets/nixarchserver-peertube.age} > /run/nixarchserver-peertube/credentials
    fi
    logo=$(base64 -w0 ${../../themes/authentik/assets/valhallishe-symbol.svg})
    export PEERTUBE_BRAND_CSS="my-header .instance-name { font-weight: 700; }
    my-header img.logo { content: url(data:image/svg+xml;base64,$logo); object-fit: contain; }"
    exec docker compose -p nixarchserver-peertube --env-file /run/nixarchserver-peertube/credentials -f ${compose} "$@"
  '';
in
pkgs.writeTextDir "nixarchserver-peertube.service" ''
  [Unit]
  Description=PeerTube on nixarchserver
  Requires=docker.service nixarchserver-awg.service
  After=docker.service nixarchserver-awg.service
  RequiresMountsFor=${storage}
  BindsTo=media-disk.mount
  After=media-disk.mount

  [Service]
  Type=oneshot
  RemainAfterExit=yes
  RuntimeDirectory=nixarchserver-peertube
  RuntimeDirectoryMode=0700
  ExecStart=${run} up -d
  ExecStop=${run} stop
  TimeoutStartSec=600

  [Install]
  WantedBy=multi-user.target
''
