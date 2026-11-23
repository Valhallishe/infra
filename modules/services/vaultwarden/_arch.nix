{ pkgs, decrypt, instance, public, ssoUrl, network }:
let
  inherit (pkgs) lib;
  dataDir = instance.storage.data.location;
  runtime = "/run/nixarchserver-vaultwarden";
  home = builtins.dirOf dataDir;
  uid = 958;
  oci = import ../../../lib/rootless-podman.nix {
    inherit pkgs home uid runtime;
    name = "vaultwarden";
    subId = 265536;
    registryRepositories = [ (builtins.head (lib.splitString "@" instance.image)) ];
  };
  environment = {
        DOMAIN = public.url;
        SIGNUPS_ALLOWED = "false";
        SSO_ENABLED = "true";
        SSO_ONLY = "true";
        SSO_AUTHORITY = "${ssoUrl}/application/o/vaultwarden/";
        SSO_SCOPES = "email profile offline_access";
        SSO_SIGNUPS_MATCH_EMAIL = "true";
        SSO_ALLOW_UNKNOWN_EMAIL_VERIFICATION = "false";
        SSO_CLIENT_CACHE_EXPIRATION = "0";
        PUSH_ENABLED = "true";
        PUSH_RELAY_URI = "https://api.bitwarden.eu";
        PUSH_IDENTITY_URI = "https://identity.bitwarden.eu";
  };
  envArgs = lib.concatStringsSep " " (lib.mapAttrsToList (key: value:
    "--env " + lib.escapeShellArg "${key}=${value}"
  ) (environment // { ROCKET_PORT = "80"; }));
  image = lib.escapeShellArg instance.image;
  resolver = pkgs.writeText "vaultwarden-resolv.conf" "nameserver 1.1.1.1\n";
  prepare = pkgs.writeShellScript "vaultwarden-prepare" ''
    set -euo pipefail
    umask 077
    ${decrypt instance.secretFile} > "$1/vaultwarden.env"
    test -s ${lib.escapeShellArg (dataDir + "/db.sqlite3")}
  '';
  prepareRuntime = pkgs.writeShellScript "vaultwarden-prepare-runtime" ''
    set -euo pipefail
    ${oci.setup}
    ${prepare} ${runtime}
    /usr/bin/chown ${oci.account}:${oci.account} ${runtime}/vaultwarden.env
  '';
  run = pkgs.writeShellScript "vaultwarden-run" ''
    exec ${oci.podman} run --rm --name vaultwarden --pull=missing \
      --network none --userns keep-id --user ${toString uid}:${toString uid} \
      --sysctl net.ipv4.ip_unprivileged_port_start=0 --cap-drop ALL \
      --security-opt no-new-privileges --pids-limit 256 \
      --env-file ${runtime}/vaultwarden.env ${envArgs} \
      --volume ${resolver}:/etc/resolv.conf:ro \
      --volume ${lib.escapeShellArg dataDir}:/data ${image}
  '';
  connect = pkgs.writeShellScript "vaultwarden-connect" ''
    set -euo pipefail
    for attempt in {1..120}; do
      pid=$(/usr/bin/runuser -u ${oci.account} -- ${oci.podman} inspect -f '{{.State.Pid}}' vaultwarden 2>/dev/null) || pid=0
      if [[ "$pid" =~ ^[1-9][0-9]*$ ]]; then
        exec ${network}/bin/up "$pid"
      fi
      /usr/bin/sleep 1
    done
    exit 1
  '';
in
{
  inherit prepare;
  unit = pkgs.writeTextDir "nixarchserver-vaultwarden.service" ''
    [Unit]
    Description=Vaultwarden in rootless Podman
    Requires=nixarchserver-awg-service-addresses.service
    After=nixarchserver-awg-service-addresses.service
    RequiresMountsFor=${dataDir}

    [Service]
    Type=exec
    RuntimeDirectory=nixarchserver-vaultwarden
    RuntimeDirectoryMode=0711
    ExecStartPre=${prepareRuntime}
    ExecStart=/usr/bin/runuser -u ${oci.account} -- ${run}
    ExecStartPost=${connect}
    ExecStop=/usr/bin/runuser -u ${oci.account} -- ${oci.podman} stop -t 20 vaultwarden
    ExecStopPost=${network}/bin/down
    TimeoutStartSec=150
    Restart=on-failure
    RestartSec=5
    Delegate=yes
  '';
}
