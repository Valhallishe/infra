{ pkgs, public, ssoUrl, home, network, execAuthentik }:
let
  inherit (pkgs) lib;
  runtime = "/run/nixarchserver-vpn-portal";
  oci = import ../../../lib/rootless-podman.nix {
    inherit pkgs home runtime;
    name = "vpn-portal";
    uid = 952;
    subId = 658752;
    registryRepositories = [ ];
  };
  oidc = pkgs.writeText "vpn-portal-oidc.py" (builtins.readFile ./oidc.py);
  prepare = pkgs.writeShellScript "vpn-portal-prepare" ''
    set -euo pipefail
    export PATH=/usr/bin
    umask 077
    ${oci.setup}
    install -d -m 0700 -o ${oci.account} -g ${oci.account} ${home}/data
    if ! test -s ${home}/client-secret; then ${pkgs.openssl}/bin/openssl rand -hex 32 > ${home}/client-secret; fi
    if ! test -s ${home}/session-secret; then ${pkgs.openssl}/bin/openssl rand -hex 32 > ${home}/session-secret; fi
    test -s /home/krozzzis/.config/valhallishe-vpn/remnawave-token
    ${pkgs.python3}/bin/python3 - <<'PY' | ${execAuthentik}
    import json
    from pathlib import Path
    print('client_secret = ' + json.dumps(Path('${home}/client-secret').read_text().strip()))
    print(Path('${oidc}').read_text())
    PY
    ${pkgs.python3}/bin/python3 - <<'PY'
    from pathlib import Path
    token = Path('/home/krozzzis/.config/valhallishe-vpn/remnawave-token').read_text().strip()
    if not token or '\n' in token or '\r' in token:
        raise ValueError('Remnawave token must be a non-empty single line')
    env = {
        'BETTER_AUTH_SECRET': Path('${home}/session-secret').read_text().strip(),
        'OPENID_CLIENT_SECRET': Path('${home}/client-secret').read_text().strip(),
        'OPENID_CLIENT_ID': 'vpn-portal',
        'OPENID_DISCOVERY_URL': '${ssoUrl}/application/o/vpn-portal/.well-known/openid-configuration',
        'NEXT_PUBLIC_APP_URL': '${public.url}',
        'PANEL_API_URL': 'http://169.254.248.1:13001',
        'PANEL_TYPE': 'remnawave',
        'REMNAWAVE_API_KEY': token,
    }
    if any('\n' in value or '\r' in value for value in env.values()):
        raise ValueError('Unexpected newline in portal configuration')
    Path('${runtime}/portal.env').write_text("".join(f'{k}={v}\n' for k, v in env.items()))
    PY
    chown ${oci.account}:${oci.account} ${runtime}/portal.env
  '';
  resolver = pkgs.writeText "vpn-portal-resolv.conf" "nameserver 1.1.1.1\n";
  run = pkgs.writeShellScript "vpn-portal-podman-stack" ''
    set -euo pipefail
    podman() { ${oci.podman} "$@"; }
    if [[ "$1" = stop ]]; then
      if podman pod exists vpn-portal; then podman pod stop -t 30 vpn-portal; podman pod rm vpn-portal; fi
      exit 0
    fi
    "$0" stop
    podman pod create --name vpn-portal --share net --network none \
      --userns keep-id:uid=1000,gid=1000 --sysctl net.ipv4.ip_unprivileged_port_start=0
    podman run --detach --pod vpn-portal --pull=never --name vpn-portal-app \
      --user 1000:1000 --cap-drop ALL --security-opt no-new-privileges --pids-limit 512 \
      --env-file ${runtime}/portal.env --volume ${home}/data:/data \
      --volume ${resolver}:/etc/resolv.conf:ro localhost/valhallishe-vpn-portal:release
  '';
  connect = pkgs.writeShellScript "vpn-portal-connect" ''
    set -euo pipefail
    export PATH=/usr/bin
    podman() { runuser -u ${oci.account} -- ${oci.podman} "$@"; }
    infra=$(podman pod inspect -f '{{.InfraContainerID}}' vpn-portal)
    pid=$(podman inspect -f '{{.State.Pid}}' "$infra")
    ${network}/bin/up "$pid"
    for attempt in {1..120}; do
      if nsenter -t "$pid" -n curl --fail --silent --max-time 2 http://127.0.0.1/ >/dev/null; then exit 0; fi
      sleep 1
    done
    exit 1
  '';
  relayConnection = pkgs.writeShellScript "vpn-portal-remnawave-connection" ''
    set -euo pipefail
    ip=$(/usr/bin/docker inspect -f '{{(index .NetworkSettings.Networks "proxy").IPAddress}}' remnawave)
    [[ "$ip" =~ ^172\.[0-9]+\.[0-9]+\.[0-9]+$ ]]
    exec ${pkgs.socat}/bin/socat - "TCP4:$ip:3000,connect-timeout=5"
  '';
in {
  unit = pkgs.writeTextDir "nixarchserver-vpn-portal.service" ''
    [Unit]
    Description=Valhallishe Account and VPN portal in rootless Podman
    Requires=nixarchserver-awg-service-addresses.service nixarchserver-authentik.service
    After=nixarchserver-awg-service-addresses.service nixarchserver-authentik.service docker.service
    RequiresMountsFor=${home}

    [Service]
    Type=oneshot
    RemainAfterExit=yes
    RuntimeDirectory=nixarchserver-vpn-portal
    RuntimeDirectoryMode=0711
    TimeoutStartSec=300
    ExecStartPre=${prepare}
    ExecStart=/usr/bin/runuser -u ${oci.account} -- ${run} start
    ExecStartPost=${connect}
    ExecStopPost=${network}/bin/down
    ExecStopPost=/usr/bin/runuser -u ${oci.account} -- ${run} stop
    Delegate=yes
  '';
  relayUnit = pkgs.writeTextDir "nixarchserver-vpn-api-relay.service" ''
    [Unit]
    Description=Private Remnawave API relay for VPN portal
    Requires=nixarchserver-vpn-portal.service docker.service
    After=nixarchserver-vpn-portal.service docker.service
    BindsTo=nixarchserver-vpn-portal.service

    [Service]
    ExecStart=${pkgs.socat}/bin/socat TCP4-LISTEN:13001,bind=169.254.248.1,reuseaddr,fork EXEC:${relayConnection}
    Restart=on-failure
  '';
}
