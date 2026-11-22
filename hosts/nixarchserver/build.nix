{
  pkgs,
  comin,
  topology,
  endpoints,
}:
let
  inherit (pkgs) lib;
  decrypt = file: "${lib.getExe pkgs.age} --decrypt -i /etc/ssh/ssh_host_ed25519_key ${file}";
  host = topology.hosts.nixarchserver;
  target = service: {
    host = "nixarchserver";
    inherit service;
    flow = "http";
  };
  public = service: endpoints.public host.publicGateway (target service);
  authentik = import ../../modules/services/authentik/arch.nix {
    inherit pkgs decrypt;
    instance = host.services.authentik;
    branding = import ../../modules/services/authentik/branding.nix {
      inherit pkgs;
      brand = topology.branding.${host.services.authentik.branding};
    };
  };
  peertube = import ../../modules/services/peertube/arch.nix {
    inherit pkgs decrypt;
    inherit (host.services.peertube) secretFile adminEmail storage;
    inherit (host.services.peertube) mount;
    brand = topology.branding.${host.services.peertube.branding};
    public = public "peertube";
    backend = endpoints.backend (target "peertube");
    ssoUrl = (public "authentik").url;
    proxyAddress = topology.nodes.${topology.hosts.${host.publicGateway}.node}.ip;
  };
  inherit (topology.network) interface;
  awg = import ../../modules/awg/arch.nix {
    inherit pkgs decrypt;
    inherit (topology) network;
    node = topology.nodes.${host.node};
    peer = topology.nodes.${host.services.awg.peer};
  };
  cominUnit = import ../../modules/services/comin/arch.nix {
    inherit pkgs comin;
    inherit (topology) repository;
    inherit (host.services.comin) branch;
    hostname = "nixarchserver";
  };
  units = [
    {
      name = "nixarchserver-awg.service";
      source = awg.unit;
    }
  ]
  ++ lib.optionals (host.services.authentik != null) [
    {
      name = "nixarchserver-authentik.service";
      source = authentik.unit;
    }
  ]
  ++ lib.optionals (host.services.peertube != null) [
    {
      name = "nixarchserver-peertube.service";
      source = peertube.unit;
    }
    {
      name = "nixarchserver-peertube-access.service";
      source = peertube.refreshUnit;
      target = null;
    }
    {
      name = "nixarchserver-peertube-access.timer";
      source = peertube.timer;
      target = "timers.target";
    }
  ]
  ++ lib.optionals (host.services.comin != null) [
    {
      name = "comin.service";
      source = cominUnit;
      startOnSwitch = false;
    }
  ];
  unitNames = records: lib.escapeShellArgs (map (unit: unit.name) records);
  targetOf = unit: unit.target or "multi-user.target";
  startUnits = builtins.filter (unit: targetOf unit != null && (unit.startOnSwitch or true)) units;
  enableUnits = builtins.filter (unit: targetOf unit != null) units;
  preflight = pkgs.writeShellScript "nixarchserver-preflight" ''
    set -euo pipefail
    export PATH=/usr/bin
    umask 077
    directory=$(mktemp -d /run/nixarchserver-check.XXXXXXXX)
    trap 'unlink "$directory/authentik.env" 2>/dev/null || :; unlink "$directory/${interface}.conf" 2>/dev/null || :; rmdir "$directory"' EXIT
    ${lib.optionalString (host.services.authentik != null) ''
      ${authentik.command} check "$directory"
    ''}
    ${awg.prepare} "$directory"
    /usr/bin/awg-quick strip "$directory/${interface}.conf" >/dev/null
    if systemctl is-active --quiet awg-quick@${interface}.service; then
      cmp -s "$directory/${interface}.conf" /etc/amnezia/amneziawg/${interface}.conf || {
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
    install -d "$directory/multi-user.target.wants" "$directory/timers.target.wants"
    units=(${unitNames units})
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
    done
    ${lib.concatMapStringsSep "\n" (unit: ''
      ln -sfn "../${unit.name}" "$directory/${targetOf unit}.wants/${unit.name}"
    '') enableUnits}
    systemctl daemon-reload
    if systemctl is-active --quiet awg-quick@${interface}.service; then
      if ! systemctl start nixarchserver-awg.service; then
        systemctl start awg-quick@${interface}.service
        exit 1
      fi
      systemctl disable awg-quick@${interface}.service
      changed=("''${changed[@]/nixarchserver-awg.service/}")
    fi
    for unit in "''${changed[@]}"; do
      case "$unit" in
        ${lib.concatMapStringsSep "|" (unit: unit.name) startUnits}) systemctl restart "$unit" ;;
      esac
    done
    for unit in ${unitNames startUnits}; do
      systemctl start "$unit"
    done
    # Retain the activated closure independently of Comin's next candidate.
    nix-env --profile /nix/var/nix/profiles/nixarchserver --set "$system"
    # Comin restarts itself after recording the deployment when its unit changes.
  '';
in
pkgs.runCommand "nixarchserver" { } ''
  mkdir -p "$out/bin" "$out/units"
  ${lib.concatMapStringsSep "\n" (unit: ''
    ln -s ${unit.source}/${unit.name} "$out/units/${unit.name}"
  '') units}
  ln -s ${preflight} "$out/bin/preflight"
  install -m755 ${activate} "$out/bin/switch-to-configuration"
''
