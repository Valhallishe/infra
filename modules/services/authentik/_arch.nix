{ pkgs, decrypt, instance, branding, network, home, scimUrl, mailDomain }:
let
  inherit (pkgs) lib;
  inherit (instance) storage secretFile;
  runtime = "/run/nixarchserver-authentik";
  images = {
    app = "ghcr.io/goauthentik/server@sha256:46a71d75dfd3eec9bd0fb42e5e13a245394e1be2d0828eebfbb2662421e66a35";
    postgres = "docker.io/library/postgres@sha256:890480b08124ce7f79960a9bb16fe39729aa302bd384bfd7c408fee6c8f7adb7";
  };
  oci = import ../../../lib/rootless-podman.nix {
    inherit pkgs home runtime;
    name = "authentik";
    uid = 953;
    subId = 593216;
    registryRepositories = [ "ghcr.io/goauthentik/server" "docker.io/library/postgres" ];
  };
  resolver = pkgs.writeText "authentik-resolv.conf" "nameserver 1.1.1.1\n";
  command = pkgs.writeShellScript "authentik-preflight" ''
    set -euo pipefail
    umask 077
    test "$(cat ${lib.escapeShellArg "${storage.database.location}/PG_VERSION"})" = 16
    for path in ${lib.escapeShellArgs (map (area: area.location) [ storage.data storage.templates storage.certificates ])}; do
      test -d "$path"
    done
    ${decrypt secretFile} > "$2/authentik.env"
    test -s "$2/authentik.env"
  '';
  prepare = pkgs.writeShellScript "authentik-podman-prepare" ''
    set -euo pipefail
    umask 077
    ${oci.setup}
    ${command} check ${runtime}
    ${pkgs.python3}/bin/python - "${runtime}" <<'PYTHON'
    import sys
    from pathlib import Path

    runtime = Path(sys.argv[1])
    source = runtime / "authentik.env"
    secrets = dict(line.split("=", 1) for line in source.read_text().splitlines() if "=" in line)
    password = secrets["PG_PASS"]
    (runtime / "database.env").write_text(f"POSTGRES_PASSWORD={password}\n")
    (runtime / "app.env").write_text(
        f"AUTHENTIK_POSTGRESQL__PASSWORD={password}\n"
        f'AUTHENTIK_SECRET_KEY={secrets["AUTHENTIK_SECRET_KEY"]}\n'
    )
    PYTHON
    /usr/bin/chown ${oci.account}:${oci.account} ${runtime}/{database,app}.env
  '';
  stack = pkgs.writeShellScript "authentik-podman-stack" ''
    set -euo pipefail
    export PATH=/usr/bin
    podman() { ${oci.podman} "$@"; }
    if [[ $1 == stop ]]; then
      if podman pod exists authentik; then
        podman pod stop -t 45 authentik
        podman pod rm authentik
      fi
      exit 0
    fi

    podman pod create --name authentik --share net --network none \
      --userns keep-id:uid=1000,gid=1000 --sysctl net.ipv4.ip_unprivileged_port_start=0
    common=(--detach --pod authentik --pull=missing --restart=on-failure \
      --security-opt no-new-privileges --cap-drop ALL --pids-limit 768 \
      --volume ${resolver}:/etc/resolv.conf:ro)
    podman run "''${common[@]}" --name authentik-postgresql --user 70:70 \
      --env-file ${runtime}/database.env --env POSTGRES_DB=authentik --env POSTGRES_USER=authentik \
      --volume ${lib.escapeShellArg "${storage.database.location}:/var/lib/postgresql/data"} \
      ${images.postgres}

    app=(--user 1000:1000 --shm-size 512m \
      --env-file ${runtime}/app.env --env AUTHENTIK_POSTGRESQL__HOST=127.0.0.1 \
      --env AUTHENTIK_POSTGRESQL__NAME=authentik --env AUTHENTIK_POSTGRESQL__USER=authentik \
      --env AUTHENTIK_LISTEN__HTTP=0.0.0.0:80 --env AUTHENTIK_LISTEN__HTTPS=0.0.0.0:443 \
      --env AUTHENTIK_ERROR_REPORTING__ENABLED=true \
      --volume ${lib.escapeShellArg "${storage.data.location}:/data"} \
      --volume ${lib.escapeShellArg "${storage.templates.location}:/templates:ro"})
    podman run "''${common[@]}" "''${app[@]}" --name authentik-server \
      --volume ${branding}:/opt/infra-branding:ro ${images.app} server
    podman run "''${common[@]}" "''${app[@]}" --name authentik-worker \
      --env AUTHENTIK_LISTEN__HTTP=127.0.0.1:9000 --env AUTHENTIK_LISTEN__METRICS=127.0.0.1:9301 \
      --volume ${lib.escapeShellArg "${storage.certificates.location}:/certs"} \
      ${images.app} worker
  '';
  scim = pkgs.writeText "authentik-inbuxa-scim.py" ''
    from authentik.providers.scim.models import SCIMProvider

    provider = SCIMProvider.objects.get(name="Inbuxa SCIM")
    url = ${builtins.toJSON scimUrl}
    if provider.url != url:
        provider.url = url
        provider.save(update_fields=["url"])
  '';
  enrollment = pkgs.writeText "authentik-enrollment.py" ''
    MAIL_DOMAIN = ${builtins.toJSON mailDomain}
    ${builtins.readFile ./enrollment.py}
  '';
  connect = pkgs.writeShellScript "authentik-connect" ''
    set -euo pipefail
    export PATH=/usr/bin
    podman() { runuser -u ${oci.account} -- ${oci.podman} "$@"; }
    infra=$(podman pod inspect -f '{{.InfraContainerID}}' authentik)
    pid=$(podman inspect -f '{{.State.Pid}}' "$infra")
    ${network}/bin/up "$pid"
    for attempt in {1..90}; do
      if nsenter -t "$pid" -n curl -fsS --max-time 3 http://127.0.0.1/-/health/ready/ >/dev/null &&
         podman exec authentik-worker ak healthcheck >/dev/null 2>&1; then
        podman exec authentik-server ak shell -c 'import runpy; runpy.run_path("/opt/infra-branding/apply.py")'
        ${execWorker} < ${scim}
        ${execWorker} < ${enrollment}
        ${execWorker} < ${./devops-access.py}
        exit 0
      fi
      sleep 1
    done
    exit 1
  '';
  execWorker = pkgs.writeShellScript "authentik-exec-worker" ''
    cd /
    exec /usr/bin/runuser -u ${oci.account} -- ${oci.podman} exec -i -e AUTHENTIK_LOG_LEVEL=error authentik-worker ak shell --no-imports
  '';
in
{
  inherit command execWorker;
  unit = pkgs.writeTextDir "nixarchserver-authentik.service" ''
    [Unit]
    Description=Authentik in rootless Podman
    Requires=nixarchserver-awg-service-addresses.service
    After=nixarchserver-awg-service-addresses.service
    RequiresMountsFor=${home}

    [Service]
    Type=oneshot
    RemainAfterExit=yes
    RuntimeDirectory=nixarchserver-authentik
    RuntimeDirectoryMode=0711
    TimeoutStartSec=300
    ExecStartPre=${prepare}
    ExecStart=/usr/bin/runuser -u ${oci.account} -- ${stack} start
    ExecStartPost=${connect}
    ExecStopPost=${network}/bin/down
    ExecStopPost=/usr/bin/runuser -u ${oci.account} -- ${stack} stop
    Delegate=yes
  '';
}
