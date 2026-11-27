{ pkgs, decrypt, instance, network }:
let
  inherit (pkgs) lib;
  inherit (instance) storage;
  runtime = "/run/nixarchserver-immich";
  home = builtins.dirOf storage.database.location;
  mounts = import ../../../lib/storage-mounts.nix { inherit lib; } [ storage.library storage.database ];
  images = {
    server = "ghcr.io/immich-app/immich-server@sha256:fc880c1bf665b4aab1e74c15e56ab871225989cd546536e6b77e771869af06bd";
    machineLearning = "ghcr.io/immich-app/immich-machine-learning@sha256:739405742a79bd7447227c553bb62ed5491aa36acf00bc667af7f9c93b6fae91";
    redis = "docker.io/valkey/valkey@sha256:facc1d2c3462975c34e10fccb167bfa92b0e0dbd992fc282c29a61c3243afb11";
    database = "ghcr.io/immich-app/postgres@sha256:32324a2f41df5de9efe1af166b7008c3f55646f8d0e00d9550c16c9822366b4a";
  };
  oci = import ../../../lib/rootless-podman.nix {
    inherit pkgs home runtime;
    name = "immich";
    uid = 957;
    subId = 331072;
    registryRepositories = map (image: builtins.head (lib.splitString "@" image)) (builtins.attrValues images);
  };
  resolver = pkgs.writeText "immich-resolv.conf" "nameserver 1.1.1.1\n";
  hosts = pkgs.writeText "immich-hosts" ''
    127.0.0.1 localhost database redis immich-machine-learning
    ::1 localhost
  '';
  prepare = pkgs.writeShellScript "immich-prepare" ''
    set -euo pipefail
    umask 077
    ${mounts.check}
    test -d ${lib.escapeShellArg storage.library.location}
    test -s ${lib.escapeShellArg (storage.database.location + "/PG_VERSION")}
    test -d ${lib.escapeShellArg storage.modelCache.location}
    test -d ${lib.escapeShellArg storage.redis.location}
    ${decrypt instance.secretFile} > "$1/immich.env"
    test -s "$1/immich.env"
  '';
  prepareRuntime = pkgs.writeShellScript "immich-prepare-runtime" ''
    set -euo pipefail
    ${oci.setup}
    ${prepare} ${runtime}
    /usr/bin/chown ${oci.account}:${oci.account} ${runtime}/immich.env
  '';
  command = pkgs.writeShellScript "immich-podman-stack" ''
    set -euo pipefail
    export PATH=/usr/bin
    podman() { ${oci.podman} "$@"; }
    if [[ "$1" = stop ]]; then
      if podman pod exists immich; then
        podman pod stop -t 30 immich
        podman pod rm immich
      fi
      exit 0
    fi

    "$0" stop
    podman pod create --name immich --share net --network none \
      --sysctl net.ipv4.ip_unprivileged_port_start=0

    common=(--detach --pod immich --pull=missing --restart=on-failure \
      --security-opt no-new-privileges --pids-limit 768 \
      --volume ${resolver}:/etc/resolv.conf:ro --volume ${hosts}:/etc/hosts:ro)
    podman run "''${common[@]}" --name immich_postgres \
      --cap-drop ALL --cap-add CHOWN,SETUID,SETGID,DAC_OVERRIDE,FOWNER --shm-size 128m \
      --env-file ${runtime}/immich.env --env POSTGRES_USER=postgres --env POSTGRES_DB=immich \
      --volume ${lib.escapeShellArg "${storage.database.location}:/var/lib/postgresql/data"} \
      ${images.database}
    podman run "''${common[@]}" --name immich_redis \
      --user 999:999 --cap-drop ALL \
      --volume ${lib.escapeShellArg "${storage.redis.location}:/data"} \
      ${images.redis}
    podman run "''${common[@]}" --name immich_machine_learning --cap-drop ALL \
      --volume ${lib.escapeShellArg "${storage.modelCache.location}:/cache"} \
      ${images.machineLearning}
    podman run "''${common[@]}" --name immich_server --cap-drop ALL \
      --env-file ${runtime}/immich.env --env IMMICH_PORT=80 \
      --env DB_HOSTNAME=127.0.0.1 --env REDIS_HOSTNAME=127.0.0.1 \
      --volume ${lib.escapeShellArg "${storage.library.location}:/data"} \
      --volume /etc/localtime:/etc/localtime:ro \
      ${images.server}
  '';
  connect = pkgs.writeShellScript "immich-connect" ''
    set -euo pipefail
    export PATH=/usr/bin
    podman() { runuser -u ${oci.account} -- ${oci.podman} "$@"; }
    infra=$(podman pod inspect -f '{{.InfraContainerID}}' immich)
    pid=$(podman inspect -f '{{.State.Pid}}' "$infra")
    ${network}/bin/up "$pid"
    for attempt in {1..90}; do
      if nsenter -t "$pid" -n curl --fail --silent --max-time 2 http://127.0.0.1:80/api/server/ping >/dev/null; then
        exit 0
      fi
      sleep 1
    done
    exit 1
  '';
in
{
  inherit prepare;
  unit = pkgs.writeTextDir "nixarchserver-immich.service" ''
    [Unit]
    Description=Immich in rootless Podman
    Requires=nixarchserver-awg-service-addresses.service
    After=nixarchserver-awg-service-addresses.service
    ${mounts.unitConfig}

    [Service]
    Type=oneshot
    RemainAfterExit=yes
    RuntimeDirectory=nixarchserver-immich
    RuntimeDirectoryMode=0711
    TimeoutStartSec=300
    ExecStartPre=${prepareRuntime}
    ExecStart=/usr/bin/runuser -u ${oci.account} -- ${command} start
    ExecStartPost=${connect}
    ExecStopPost=${network}/bin/down
    ExecStopPost=/usr/bin/runuser -u ${oci.account} -- ${command} stop
    Delegate=yes
  '';
}
