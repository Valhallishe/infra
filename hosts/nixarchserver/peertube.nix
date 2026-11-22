{ pkgs, decrypt }:
let
  storage = "/media/disk/peertube";
  runtime = "/run/nixarchserver-peertube";
  quota = 50 * 1024 * 1024 * 1024;
  accessSettings = pkgs.writeText "peertube-access.json" (builtins.toJSON {
    accessGroup = "PeerTube Access";
    publishGroup = "PeerTube Publishers";
    snapshotLifetime = 120;
  });
  pluginSettings = pkgs.writeText "peertube-oidc.json" (builtins.toJSON {
    auth-display-name = "Valhallishe SSO";
    discover-url = "https://sso.valhallishe.net/application/o/peertube/.well-known/openid-configuration";
    client-id = "peertube";
    scope = "openid profile email";
    username-property = "preferred_username";
    mail-property = "email";
    external-id-property = "sub";
  });
  manifest = pkgs.writeText "package.json" (builtins.toJSON {
    name = "peertube-plugin-valhallishe-publish";
    version = "1.0.0";
    description = "Enforce Authentik membership for publishing videos";
    homepage = "https://github.com/Valhallishe/infra";
    author = "Valhallishe";
    bugs = "https://github.com/Valhallishe/infra/issues";
    engine.peertube = ">=8.3.0 <9";
    library = "./main.cjs";
  });
  publishPlugin = pkgs.runCommand "peertube-plugin-valhallishe-publish" {} ''
    mkdir -p "$out"
    cp ${./peertube-publish.cjs} "$out/main.cjs"
    cp ${manifest} "$out/package.json"
  '';
  pluginPath = "/opt/${baseNameOf (toString publishPlugin)}/peertube-plugin-valhallishe-publish";
  entrypoint = pkgs.writeText "peertube-entrypoint" ''
    set -eu
    /usr/local/bin/entrypoint.sh node dist/scripts/plugin/install.js --plugin-path ${pluginPath}
    exec /usr/local/bin/entrypoint.sh "$@"
  '';
  refresh = pkgs.writeShellScript "peertube-access-refresh" ''
    set -euo pipefail
    export PATH=/usr/bin
    umask 077
    snapshot=$(mktemp "${runtime}/access/.publish.XXXXXXXX")
    trap 'rm -f "$snapshot"' EXIT
    ${pkgs.python3}/bin/python - ${accessSettings} "${runtime}/credentials" "$1" <<'PYTHON' |
    import json
    import sys
    from pathlib import Path

    print("settings = " + repr(json.loads(Path(sys.argv[1]).read_text())))
    configure = sys.argv[3] == "configure"
    print("configure = " + repr(configure))
    if configure:
        credentials = dict(line.split("=", 1) for line in Path(sys.argv[2]).read_text().splitlines())
        print("client_secret = " + repr(credentials["OIDC_SECRET"]))
    print(Path("${./peertube-oidc.py}").read_text())
    PYTHON
      docker exec -i -e AUTHENTIK_LOG_LEVEL=error authentik-worker-1 ak shell --no-imports |
      sed -n 's/^PEERTUBE_PUBLISH=//p' > "$snapshot"
    test -s "$snapshot"
    chmod 0644 "$snapshot"
    mv -f "$snapshot" "${runtime}/access/publish.json"
  '';
  setup = pkgs.writeShellScript "peertube-setup" ''
    set -euo pipefail
    export PATH=/usr/bin
    curl -fsS --retry 30 --retry-delay 2 --retry-all-errors --max-time 5 \
      -H 'Host: videos.valhallishe.net' http://10.1.0.2:9001/api/v1/config >/dev/null
    ${pkgs.python3}/bin/python ${./peertube-plugin.py} ${pluginSettings}
    ${refresh} configure
    docker exec -i nixarchserver-peertube-postgres-1 psql -X -v ON_ERROR_STOP=1 -U peertube <<'SQL'
    UPDATE "user" SET "videoQuota" = ${toString quota}
    WHERE "pluginAuth" = 'peertube-plugin-auth-openid-connect' AND "videoQuota" = -1;
    SQL
  '';
  compose = pkgs.writeText "peertube-compose.json" (builtins.toJSON {
    services = {
      peertube = {
        image = "chocobozzz/peertube:v8.3.2";
        ports = [ "10.1.0.2:9001:9000" ];
        volumes = [
          "${storage}:/data"
          "config:/config"
          "${runtime}/access:/run/peertube-access:ro"
          "${publishPlugin}:${pluginPath}:ro"
          "${entrypoint}:/opt/peertube-entrypoint:ro"
        ];
        entrypoint = [ "/bin/sh" "/opt/peertube-entrypoint" ];
        command = [ "node" "dist/server" ];
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
          PEERTUBE_SIGNUP_ENABLED = "false";
          PEERTUBE_VIDEO_STUDIO_ENABLED = "true";
          PEERTUBE_VIDEO_STUDIO_REMOTE_RUNNERS_ENABLED = "false";
          PEERTUBE_USER_VIDEO_QUOTA = toString quota;
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
      install -d -m 0755 ${runtime}/access
      ${decrypt ../../secrets/nixarchserver-peertube.age} > /run/nixarchserver-peertube/credentials
    fi
    logo=$(base64 -w0 ${../../themes/authentik/assets/valhallishe-symbol.svg})
    export PEERTUBE_BRAND_CSS="my-header .instance-name { font-weight: 700; }
    my-header img.logo { content: url(data:image/svg+xml;base64,$logo); object-fit: contain; }"
    exec docker compose -p nixarchserver-peertube --env-file /run/nixarchserver-peertube/credentials -f ${compose} "$@"
  '';
in
{
  unit = pkgs.writeTextDir "nixarchserver-peertube.service" ''
    [Unit]
    Description=PeerTube on nixarchserver
    Requires=docker.service nixarchserver-awg.service nixarchserver-authentik.service
    After=docker.service nixarchserver-awg.service nixarchserver-authentik.service
    RequiresMountsFor=${storage}
    BindsTo=media-disk.mount
    After=media-disk.mount

    [Service]
    Type=oneshot
    RemainAfterExit=yes
    RuntimeDirectory=nixarchserver-peertube
    RuntimeDirectoryMode=0700
    ExecStart=${run} up -d
    ExecStartPost=${setup}
    ExecStop=${run} stop
    TimeoutStartSec=600

    [Install]
    WantedBy=multi-user.target
  '';

  refreshUnit = pkgs.writeTextDir "nixarchserver-peertube-access.service" ''
    [Unit]
    Description=Refresh PeerTube publishing permissions
    After=nixarchserver-peertube.service
    Requisite=nixarchserver-peertube.service

    [Service]
    Type=oneshot
    ExecStart=${refresh} refresh
    TimeoutStartSec=25
  '';
  timer = pkgs.writeTextDir "nixarchserver-peertube-access.timer" ''
    [Unit]
    Description=Refresh PeerTube publishing permissions every 30 seconds

    [Timer]
    OnActiveSec=5s
    OnUnitInactiveSec=30s
    AccuracySec=1s

    [Install]
    WantedBy=timers.target
  '';
}
