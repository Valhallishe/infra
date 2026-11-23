{ pkgs, decrypt, instance, backend }:
let
  inherit (pkgs) lib;
  inherit (instance) storage;
  runtime = "/run/nixarchserver-immich";
  mounts = import ../../../lib/storage-mounts.nix { inherit lib; } [ storage.library storage.database ];
  compose = pkgs.writeText "immich-compose.json" (builtins.toJSON {
    services = {
      immich-server = {
        image = "ghcr.io/immich-app/immich-server@sha256:fc880c1bf665b4aab1e74c15e56ab871225989cd546536e6b77e771869af06bd";
        container_name = "immich_server";
        env_file = [ "${runtime}/immich.env" ];
        ports = [ "${toString backend.port}:2283" ];
        volumes = [ "${storage.library.location}:/data" "/etc/localtime:/etc/localtime:ro" ];
        depends_on = [ "redis" "database" ];
        restart = "always";
      };
      immich-machine-learning = {
        image = "ghcr.io/immich-app/immich-machine-learning@sha256:739405742a79bd7447227c553bb62ed5491aa36acf00bc667af7f9c93b6fae91";
        container_name = "immich_machine_learning";
        env_file = [ "${runtime}/immich.env" ];
        volumes = [ "model-cache:/cache" ];
        restart = "always";
      };
      redis = {
        image = "docker.io/valkey/valkey:8-bookworm@sha256:facc1d2c3462975c34e10fccb167bfa92b0e0dbd992fc282c29a61c3243afb11";
        container_name = "immich_redis";
        healthcheck.test = [ "CMD-SHELL" "redis-cli ping || exit 1" ];
        restart = "always";
      };
      database = {
        image = "ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0@sha256:32324a2f41df5de9efe1af166b7008c3f55646f8d0e00d9550c16c9822366b4a";
        container_name = "immich_postgres";
        environment = {
          POSTGRES_PASSWORD = "\${DB_PASSWORD:?missing database password}";
          POSTGRES_USER = "postgres";
          POSTGRES_DB = "immich";
          POSTGRES_INITDB_ARGS = "--data-checksums";
        };
        volumes = [ "${storage.database.location}:/var/lib/postgresql/data" ];
        shm_size = "128mb";
        restart = "always";
      };
    };
    volumes.model-cache.name = storage.modelCache.location;
  });
  prepare = pkgs.writeShellScript "immich-prepare" ''
    set -euo pipefail
    umask 077
    ${mounts.check}
    test -d ${lib.escapeShellArg storage.library.location}
    test -s ${lib.escapeShellArg (storage.database.location + "/PG_VERSION")}
    ${decrypt instance.secretFile} > "$1/immich.env"
    test -s "$1/immich.env"
  '';
  command = pkgs.writeShellScript "immich-compose" ''
    set -euo pipefail
    exec /usr/bin/docker compose --project-name immich --project-directory ${lib.escapeShellArg storage.project.location} --env-file ${runtime}/immich.env -f ${compose} "$@"
  '';
in
{
  inherit prepare;
  unit = pkgs.writeTextDir "nixarchserver-immich.service" ''
    [Unit]
    Description=Immich on nixarchserver
    Requires=docker.service
    After=docker.service
    ${mounts.unitConfig}

    [Service]
    Type=oneshot
    RemainAfterExit=yes
    RuntimeDirectory=nixarchserver-immich
    RuntimeDirectoryMode=0700
    TimeoutStartSec=240
    ExecStartPre=${prepare} %t/nixarchserver-immich
    ExecStart=${command} up -d --wait --wait-timeout 180
    ExecStop=${command} stop
  '';
}
