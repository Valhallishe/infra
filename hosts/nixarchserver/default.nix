{ pkgs, comin }:
let
  inherit (pkgs) lib;
  decrypt = file: "${lib.getExe pkgs.age} --decrypt -i /etc/ssh/ssh_host_ed25519_key ${file}";
  authentik = import ./authentik.nix { inherit pkgs decrypt; };
  peertube = import ./peertube.nix { inherit pkgs decrypt; };
  awg = import ./awg.nix { inherit pkgs decrypt; };
  cominConfig = pkgs.writeText "comin-nixarchserver.json" (builtins.toJSON {
    hostname = "nixarchserver";
    state_dir = "/var/lib/comin";
    repository_type = "flake";
    exporter.listen_address = "127.0.0.1";
    grpc.unix_socket_mode = "0600";
    retention = {
      deployment_boot_entry_capacity = 5;
      deployment_successful_capacity = 5;
      deployment_any_capacity = 10;
    };
    build_confirmer.mode = "without";
    deploy_confirmer.mode = "without";
    remotes = [{
      name = "origin";
      url = "https://github.com/Valhallishe/infra.git";
      poller.period = 60;
      branches.main = { name = "main"; operation = "switch"; };
    }];
  });
  cominUnit = pkgs.writeTextDir "comin.service" ''
    [Unit]
    Description=Comin GitOps for nixarchserver
    Wants=network-online.target
    Requires=nix-daemon.socket
    After=network-online.target nix-daemon.socket

    [Service]
    Environment="PATH=/nix/var/nix/profiles/default/bin:/usr/bin"
    Environment="NIX_CONFIG=experimental-features = nix-command flakes"
    ExecStart=${lib.getExe comin} run --config ${cominConfig}
    Restart=always
    RestartSec=5

    [Install]
    WantedBy=multi-user.target
  '';
  preflight = pkgs.writeShellScript "nixarchserver-preflight" ''
    set -euo pipefail
    export PATH=/usr/bin
    umask 077
    directory=$(mktemp -d /run/nixarchserver-check.XXXXXXXX)
    trap 'unlink "$directory/authentik.env" 2>/dev/null || :; unlink "$directory/infra0.conf" 2>/dev/null || :; rmdir "$directory"' EXIT
    ${authentik.command} check "$directory"
    ${awg.prepare} "$directory"
    /usr/bin/awg-quick strip "$directory/infra0.conf" >/dev/null
    if systemctl is-active --quiet awg-quick@infra0.service; then
      cmp -s "$directory/infra0.conf" /etc/amnezia/amneziawg/infra0.conf || {
        echo "Rendered AWG config differs from the legacy Arch config" >&2
        exit 1
      }
    fi
  '';
  activate = pkgs.writeShellScript "switch-to-configuration" ''
    set -euo pipefail
    export PATH=/nix/var/nix/profiles/default/bin:/usr/bin
    [[ ''${1:-} = switch ]] || { echo "nixarchserver supports only switch" >&2; exit 2; }
    system=$(dirname "$(dirname "$(readlink -f "$0")")")
    exec 9>/run/lock/nixarchserver.lock
    flock 9
    "$system/bin/preflight"

    directory=/etc/systemd/system
    install -d "$directory/multi-user.target.wants"
    units=(nixarchserver-awg.service nixarchserver-authentik.service nixarchserver-peertube.service comin.service)
    for unit in "''${units[@]}"; do
      path="$directory/$unit"
      if [[ -e $path && $(readlink "$path" || :) != /nix/store/*/"$unit" ]]; then
        echo "Refusing to replace existing $path" >&2
        exit 1
      fi
    done

    changed=()
    for unit in "''${units[@]}"; do
      source=$(readlink -f "$system/units/$unit")
      if [[ $(readlink "$directory/$unit" || :) != "$source" ]]; then
        ln -sfn "$source" "$directory/$unit"
        changed+=("$unit")
      fi
      ln -sfn "../$unit" "$directory/multi-user.target.wants/$unit"
    done
    systemctl daemon-reload
    if systemctl is-active --quiet awg-quick@infra0.service; then
      if ! systemctl start nixarchserver-awg.service; then
        systemctl start awg-quick@infra0.service
        exit 1
      fi
      systemctl disable awg-quick@infra0.service
      changed=("''${changed[@]/nixarchserver-awg.service/}")
    fi
    for unit in "''${changed[@]}"; do
      if [[ -n $unit && $unit != comin.service ]]; then
        systemctl restart "$unit"
      fi
    done
    systemctl start nixarchserver-awg.service nixarchserver-authentik.service
    systemctl start nixarchserver-peertube.service
    # Retain the activated closure independently of Comin's next candidate.
    nix-env --profile /nix/var/nix/profiles/nixarchserver --set "$system"
    # Comin restarts itself after recording the deployment when its unit changes.
  '';
in
pkgs.runCommand "nixarchserver" { } ''
  mkdir -p "$out/bin" "$out/units"
  ln -s ${authentik.unit}/nixarchserver-authentik.service "$out/units/nixarchserver-authentik.service"
  ln -s ${awg.unit}/nixarchserver-awg.service "$out/units/nixarchserver-awg.service"
  ln -s ${peertube}/nixarchserver-peertube.service "$out/units/nixarchserver-peertube.service"
  ln -s ${cominUnit}/comin.service "$out/units/comin.service"
  ln -s ${preflight} "$out/bin/preflight"
  install -m755 ${activate} "$out/bin/switch-to-configuration"
''
