{
  pkgs,
  decrypt,
  secretFile,
  public,
  network,
  home,
  ssoUrl,
  adminEmail,
  proxyAddress,
  storage,
  brand,
}:
let
  inherit (pkgs) lib;
  files = storage.files.location;
  mounts = import ../../../lib/storage-mounts.nix { inherit lib; } [ storage.files ];
  apiUrl = "http://127.0.0.1/api/v1";
  credentials = "${runtime}/credentials";
  runtime = "/run/nixarchserver-peertube";
  quota = 50 * 1024 * 1024 * 1024;
  accessSettings = pkgs.writeText "peertube-access.json" (
    builtins.toJSON {
      accessGroup = "PeerTube Access";
      publishGroup = "PeerTube Publishers";
      snapshotLifetime = 120;
      displayName = "${brand.name} Videos";
      redirectUri = "${public.url}/plugins/auth-openid-connect/router/code-cb";
    }
  );
  pluginSettings = pkgs.writeText "peertube-oidc.json" (
    builtins.toJSON {
      auth-display-name = "${brand.name} SSO";
      discover-url = "${ssoUrl}/application/o/peertube/.well-known/openid-configuration";
      client-id = "peertube";
      scope = "openid profile email";
      username-property = "preferred_username";
      mail-property = "email";
      external-id-property = "sub";
    }
  );
  manifest = pkgs.writeText "package.json" (
    builtins.toJSON {
      name = "peertube-plugin-valhallishe-publish";
      version = "1.0.0";
      description = "Enforce Authentik membership for publishing videos";
      homepage = "https://github.com/Valhallishe/infra";
      author = brand.name;
      bugs = "https://github.com/Valhallishe/infra/issues";
      engine.peertube = ">=8.3.0 <9";
      library = "./main.cjs";
    }
  );
  publishPlugin = pkgs.runCommand "peertube-plugin-valhallishe-publish" { } ''
    mkdir -p "$out"
    cp ${./publish.cjs} "$out/main.cjs"
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
    ${pkgs.python3}/bin/python - ${accessSettings} "${credentials}" "$1" <<'PYTHON' |
    import json
    import sys
    from pathlib import Path

    print("settings = " + repr(json.loads(Path(sys.argv[1]).read_text())))
    configure = sys.argv[3] == "configure"
    print("configure = " + repr(configure))
    if configure:
        credentials = dict(line.split("=", 1) for line in Path(sys.argv[2]).read_text().splitlines())
        print("client_secret = " + repr(credentials["OIDC_SECRET"]))
    print(Path("${./oidc.py}").read_text())
    PYTHON
      docker exec -i -e AUTHENTIK_LOG_LEVEL=error authentik-worker-1 ak shell --no-imports |
      sed -n 's/^PEERTUBE_PUBLISH=//p' > "$snapshot"
    test -s "$snapshot"
    chgrp ${oci.account} "$snapshot"
    chmod 0640 "$snapshot"
    mv -f "$snapshot" "${runtime}/access/publish.json"
  '';
  setup = pkgs.writeShellScript "peertube-setup" ''
    set -euo pipefail
    export PATH=/usr/bin
    podman() { runuser -u ${oci.account} -- ${oci.podman} "$@"; }
    infra=$(podman pod inspect -f '{{.InfraContainerID}}' peertube)
    pid=$(podman inspect -f '{{.State.Pid}}' "$infra")
    ${network}/bin/up "$pid"
    nsenter -t "$pid" -n curl -fsS --retry 30 --retry-delay 2 --retry-all-errors --max-time 5 \
      -H ${lib.escapeShellArg "Host: ${public.authority}"} ${lib.escapeShellArg "${apiUrl}/config"} >/dev/null
    nsenter -t "$pid" -n ${pkgs.python3}/bin/python ${./plugin.py} ${pluginSettings} "${credentials}" \
      ${lib.escapeShellArgs [
        apiUrl
        public.authority
        public.protocol
      ]}
    ${refresh} configure
    podman exec -i peertube-postgres psql -X -v ON_ERROR_STOP=1 -U peertube <<'SQL'
    UPDATE "user" SET "videoQuota" = ${toString quota}
    WHERE "pluginAuth" = 'peertube-plugin-auth-openid-connect' AND "videoQuota" = -1;
    SQL
  '';
  environment = {
    NODE_CONFIG = builtins.toJSON { listen = { hostname = "0.0.0.0"; port = 80; }; };
    PEERTUBE_DB_HOSTNAME = "postgres";
    PEERTUBE_DB_NAME = "peertube";
    PEERTUBE_DB_USERNAME = "peertube";
    PEERTUBE_REDIS_HOSTNAME = "redis";
    PEERTUBE_WEBSERVER_HOSTNAME = public.hostname;
    PEERTUBE_WEBSERVER_HTTPS = if public.protocol == "https" then "true" else "false";
    PEERTUBE_WEBSERVER_PORT = toString public.port;
    PEERTUBE_TRUST_PROXY = builtins.toJSON [
      "loopback"
      proxyAddress
    ];
    PEERTUBE_SIGNUP_ENABLED = "false";
    PEERTUBE_VIDEO_STUDIO_ENABLED = "true";
    PEERTUBE_VIDEO_STUDIO_REMOTE_RUNNERS_ENABLED = "false";
    PEERTUBE_USER_VIDEO_QUOTA = toString quota;
    PEERTUBE_ADMIN_EMAIL = adminEmail;
    PEERTUBE_INSTANCE_NAME = "${brand.name} Videos";
    PEERTUBE_INSTANCE_SHORT_DESCRIPTION = "Видеоплатформа ${brand.name}";
  };
  oci = import ../../../lib/rootless-podman.nix {
    inherit pkgs home runtime;
    name = "peertube";
    uid = 955;
    subId = 462144;
    registryRepositories = [
      "docker.io/chocobozzz/peertube"
      "docker.io/library/postgres"
      "docker.io/library/redis"
    ];
  };
  resolver = pkgs.writeText "peertube-resolv.conf" "nameserver 1.1.1.1\n";
  hosts = pkgs.writeText "peertube-hosts" "127.0.0.1 localhost postgres redis\n::1 localhost\n";
  prepare = pkgs.writeShellScript "peertube-podman-prepare" ''
    set -euo pipefail
    export PATH=/usr/bin
    umask 077
    ${oci.setup}
    ${mounts.check}
    test -s ${lib.escapeShellArg "${storage.database.location}/PG_VERSION"}
    install -d -m0750 -o root -g ${oci.account} ${runtime}/access
    ${decrypt secretFile} > "${credentials}"
    ${pkgs.python3}/bin/python - "${credentials}" "${runtime}" <<'PYTHON'
    import sys
    from pathlib import Path

    source = Path(sys.argv[1])
    runtime = Path(sys.argv[2])
    secrets = dict(line.split("=", 1) for line in source.read_text().splitlines() if "=" in line)
    password = secrets["POSTGRES_PASSWORD"]
    (runtime / "database.env").write_text(f"POSTGRES_PASSWORD={password}\n")
    (runtime / "peertube.env").write_text(
        f"PEERTUBE_DB_PASSWORD={password}\n"
        f'PEERTUBE_SECRET={secrets["PEERTUBE_SECRET"]}\n'
        f'PT_INITIAL_ROOT_PASSWORD={secrets["PEERTUBE_ADMIN_PASSWORD"]}\n'
    )
    PYTHON
    chown ${oci.account}:${oci.account} ${runtime}/{database,peertube}.env
  '';
  command = pkgs.writeShellScript "peertube-podman-stack" ''
    set -euo pipefail
    export PATH=/usr/bin
    podman() { ${oci.podman} "$@"; }
    if [[ $1 == stop ]]; then
      if podman pod exists peertube; then
        podman pod stop -t 40 peertube
        podman pod rm peertube
      fi
      exit 0
    fi

    podman pod create --name peertube --share net --network none \
      --userns keep-id:uid=999,gid=999 --sysctl net.ipv4.ip_unprivileged_port_start=0
    common=(--detach --pod peertube --pull=missing --restart=on-failure \
      --security-opt no-new-privileges --cap-drop ALL --pids-limit 768 \
      --volume ${resolver}:/etc/resolv.conf:ro --volume ${hosts}:/etc/hosts:ro)
    podman run "''${common[@]}" --name peertube-postgres --user 999:999 \
      --env-file ${runtime}/database.env --env POSTGRES_DB=peertube --env POSTGRES_USER=peertube \
      --volume ${lib.escapeShellArg "${storage.database.location}:/var/lib/postgresql/data"} \
      docker.io/library/postgres@sha256:00bc86618629af00d2937fdc5a5d63db3ff8450acf52f0636ec813c7f4902929
    podman run "''${common[@]}" --name peertube-redis --user 999:999 \
      --volume ${lib.escapeShellArg "${storage.redis.location}:/data"} \
      docker.io/library/redis@sha256:7958cfbb9d152f87dadfbc89f1b0b15938f0b81ff8982feb327476f4911935c3

    logo=$(base64 -w0 ${brand.symbol})
    export PEERTUBE_INSTANCE_CUSTOMIZATIONS_CSS="my-header .instance-name { font-weight: 700; }
    my-header img.logo { content: url(data:image/svg+xml;base64,$logo); object-fit: contain; }"
    podman run "''${common[@]}" --name peertube-app --user 999:999 \
      --env-file ${runtime}/peertube.env --env PEERTUBE_INSTANCE_CUSTOMIZATIONS_CSS \
      ${lib.concatStringsSep " " (lib.mapAttrsToList (key: value: "--env " + lib.escapeShellArg "${key}=${value}") environment)} \
      --volume ${lib.escapeShellArg "${files}:/data"} \
      --volume ${lib.escapeShellArg "${storage.config.location}:/config"} \
      --volume ${runtime}/access:/run/peertube-access:ro \
      --volume ${publishPlugin}:${pluginPath}:ro \
      --volume ${entrypoint}:/opt/peertube-entrypoint:ro --entrypoint /bin/sh \
      docker.io/chocobozzz/peertube@sha256:47f42abd101b75cdc1f644f0782428d254350c570ab0c8d60c03dff42a1ba40a \
      /opt/peertube-entrypoint node dist/server
  '';
in
{
  unit = pkgs.writeTextDir "nixarchserver-peertube.service" ''
    [Unit]
    Description=PeerTube on nixarchserver
    Requires=nixarchserver-awg-service-addresses.service nixarchserver-authentik.service
    After=nixarchserver-awg-service-addresses.service nixarchserver-authentik.service
    ${mounts.unitConfig}

    [Service]
    Type=oneshot
    RemainAfterExit=yes
    RuntimeDirectory=nixarchserver-peertube
    RuntimeDirectoryMode=0711
    ExecStartPre=${prepare}
    ExecStart=/usr/bin/runuser -u ${oci.account} -- ${command} start
    ExecStartPost=${setup}
    ExecStopPost=${network}/bin/down
    ExecStopPost=/usr/bin/runuser -u ${oci.account} -- ${command} stop
    Delegate=yes
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
