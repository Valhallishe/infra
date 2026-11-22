{
  pkgs,
  decrypt,
  instance,
  branding,
}:
let
  inherit (instance) dataDir secretFile;
  port = instance.flows.http.port;
  inherit (instance.database) volume;
  image = "ghcr.io/goauthentik/server:2026.2.1@sha256:46a71d75dfd3eec9bd0fb42e5e13a245394e1be2d0828eebfbb2662421e66a35";
  postgres = "docker.io/library/postgres:16-alpine@sha256:890480b08124ce7f79960a9bb16fe39729aa302bd384bfd7c408fee6c8f7adb7";
  app = {
    inherit image;
    restart = "unless-stopped";
    shm_size = "512mb";
    depends_on.postgresql.condition = "service_healthy";
    environment = {
      AUTHENTIK_POSTGRESQL__HOST = "postgresql";
      AUTHENTIK_POSTGRESQL__NAME = "authentik";
      AUTHENTIK_POSTGRESQL__USER = "authentik";
      AUTHENTIK_POSTGRESQL__PASSWORD = "$" + "{PG_PASS:?required}";
      AUTHENTIK_SECRET_KEY = "$" + "{AUTHENTIK_SECRET_KEY:?required}";
      AUTHENTIK_ERROR_REPORTING__ENABLED = "true";
    };
    volumes = [
      "${dataDir}/data:/data"
      "${dataDir}/custom-templates:/templates"
    ];
  };
  compose = pkgs.writeText "authentik-compose.json" (
    builtins.toJSON {
      services = {
        postgresql = {
          image = postgres;
          restart = "unless-stopped";
          environment = {
            POSTGRES_DB = "authentik";
            POSTGRES_USER = "authentik";
            POSTGRES_PASSWORD = "$" + "{PG_PASS:?required}";
          };
          volumes = [ "database:/var/lib/postgresql/data" ];
          healthcheck = {
            test = [
              "CMD"
              "pg_isready"
              "-U"
              "authentik"
              "-d"
              "authentik"
            ];
            interval = "5s";
            retries = 12;
            start_period = "20s";
            timeout = "5s";
          };
        };
        server = app // {
          command = [ "server" ];
          volumes = app.volumes ++ [ "${branding}:/opt/infra-branding:ro" ];
          ports = [
            "${toString port}:9000"
            "${toString instance.httpsPort}:9443"
          ];
        };
        worker = app // {
          command = [ "worker" ];
          user = "root";
          volumes = app.volumes ++ [
            "${dataDir}/certs:/certs"
            "/var/run/docker.sock:/var/run/docker.sock"
          ];
        };
      };
      volumes.database = {
        external = true;
        name = volume;
      };
    }
  );
  command = pkgs.writeShellScript "nixarchserver-authentik" ''
    set -euo pipefail
    umask 077
    envFile="$2/authentik.env"
    ${decrypt secretFile} > "$envFile"
    unset PG_PASS AUTHENTIK_SECRET_KEY
    docker=/usr/bin/docker
    args=(compose --project-name authentik --project-directory ${pkgs.lib.escapeShellArg dataDir} --env-file "$envFile" -f ${compose})
    mountpoint=$("$docker" volume inspect -f '{{.Mountpoint}}' ${pkgs.lib.escapeShellArg volume})
    test "$(cat "$mountpoint/PG_VERSION")" = 16
    for directory in data custom-templates certs; do
      test -d "${dataDir}/$directory"
    done
    "$docker" "''${args[@]}" config --quiet
    if [[ $1 = start ]]; then
      "$docker" "''${args[@]}" up --detach --wait --wait-timeout 120
      /usr/bin/curl -fsS --retry 20 --retry-delay 2 --retry-all-errors --max-time 5 \
        http://127.0.0.1:${toString port}/-/health/ready/
      "$docker" "''${args[@]}" exec -T server ak shell -c \
        'import runpy; runpy.run_path("/opt/infra-branding/apply.py")'
    fi
  '';
in
{
  inherit command;
  unit = pkgs.writeTextDir "nixarchserver-authentik.service" ''
    [Unit]
    Description=Authentik OCI services (nixarchserver)
    Requires=docker.service infra-docker-firewall.service
    After=docker.service infra-docker-firewall.service
    PartOf=docker.service

    [Service]
    Type=oneshot
    RemainAfterExit=yes
    RuntimeDirectory=nixarchserver-authentik
    RuntimeDirectoryMode=0700
    TimeoutStartSec=300
    ExecStart=${command} start %t/nixarchserver-authentik

    [Install]
    WantedBy=multi-user.target
  '';
}
