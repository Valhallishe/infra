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
  authentik = import ../../modules/services/authentik/_arch.nix {
    inherit pkgs decrypt;
    instance = host.services.authentik;
    branding = import ../../modules/services/authentik/_branding.nix {
      inherit pkgs;
      brand = topology.branding.${host.services.authentik.branding};
    };
  };
  peertube = import ../../modules/services/peertube/_arch.nix {
    inherit pkgs decrypt;
    inherit (host.services.peertube) secretFile adminEmail storage;
    brand = topology.branding.${host.services.peertube.branding};
    public = public "peertube";
    backend = endpoints.backend (target "peertube");
    ssoUrl = (public "authentik").url;
    proxyAddress = topology.nodes.${topology.hosts.${host.publicGateway}.node}.ip;
  };
  opencloud = import ../../modules/services/opencloud/_arch.nix {
    inherit pkgs decrypt;
    instance = host.services.opencloud;
    brand = topology.branding.${host.services.opencloud.branding};
    public = public "opencloud";
    home = "${topology.systemStorage}/opencloud";
    network = import ../../lib/routed-container-network.nix {
      inherit pkgs;
      name = "opencloud";
      serviceAddress = host.services.opencloud.overlayAddress;
      gatewaySources = with topology.nodes.halo; [ ip serviceHostIp ];
      awgInterface = topology.network.interface;
      uplinkInterface = "enp45s0";
      linkSubnet = "169.254.254";
      ports = [ host.services.opencloud.flows.http.port ];
      httpsEgress = true;
    };
    ssoUrl = (public "authentik").url;
  };
  vaultwarden = import ../../modules/services/vaultwarden/_arch.nix {
    inherit pkgs decrypt;
    instance = host.services.vaultwarden;
    public = public "vaultwarden";
    network = import ../../lib/routed-container-network.nix {
      inherit pkgs;
      name = "vault";
      serviceAddress = host.services.vaultwarden.overlayAddress;
      gatewaySources = with topology.nodes.halo; [ ip serviceHostIp ];
      awgInterface = topology.network.interface;
      uplinkInterface = "enp45s0";
      linkSubnet = "169.254.252";
      ports = [ host.services.vaultwarden.flows.http.port ];
      httpsEgress = true;
    };
    ssoUrl = (public "authentik").url;
  };
  immich = import ../../modules/services/immich/_arch.nix {
    inherit pkgs decrypt;
    instance = host.services.immich;
    network = import ../../lib/routed-container-network.nix {
      inherit pkgs;
      name = "immich";
      serviceAddress = host.services.immich.overlayAddress;
      gatewaySources = with topology.nodes.halo; [ ip serviceHostIp ];
      awgInterface = topology.network.interface;
      uplinkInterface = "enp45s0";
      linkSubnet = "169.254.253";
      ports = [ host.services.immich.flows.http.port ];
      httpsEgress = true;
    };
  };
  inbuxaConfig = import ../../modules/services/inbuxa/_package.nix {
    inherit pkgs endpoints topology;
    hostname = "nixarchserver";
  };
  inbuxaUnit = pkgs.writeTextDir "infra-inbuxa.service" ''
    [Unit]
    Description=Inbuxa containers
    Requires=docker.service
    Wants=nixarchserver-awg.service
    After=docker.service nixarchserver-awg.service
    RequiresMountsFor=${host.services.inbuxa.storage.config.location} ${host.services.inbuxa.storage.mail.location}

    [Service]
    Type=oneshot
    RemainAfterExit=yes
    WorkingDirectory=${host.services.inbuxa.storage.project.location}
    RuntimeDirectory=infra-inbuxa
    RuntimeDirectoryMode=0700
    ExecStartPre=${inbuxaPrepare} %t/infra-inbuxa
    ExecStart=/usr/bin/docker compose --project-name infra-inbuxa --project-directory ${host.services.inbuxa.storage.project.location} -f ${inbuxaConfig}/compose.yaml up -d --no-build --pull never
    ExecStop=/usr/bin/docker compose --project-name infra-inbuxa --project-directory ${host.services.inbuxa.storage.project.location} -f ${inbuxaConfig}/compose.yaml stop
    TimeoutStartSec=120

    [Install]
    WantedBy=multi-user.target
  '';
  inbuxaPrepare = pkgs.writeShellScript "inbuxa-prepare" ''
    set -euo pipefail
    umask 077
    test -d ${lib.escapeShellArg host.services.inbuxa.storage.config.location}
    test -d ${lib.escapeShellArg host.services.inbuxa.storage.mail.location}
    ${decrypt ../../secrets/nixarchserver-inbuxa.age} > "$1/webmail-secrets.env"
    test -s "$1/webmail-secrets.env"
  '';
  inherit (topology.network) interface;
  awg = import ../../modules/awg/_arch.nix {
    inherit pkgs decrypt;
    inherit (topology) network;
    node = topology.nodes.${host.node};
    peer = topology.nodes.${host.services.awg.peer};
  };
  cominUnit = import ../../modules/services/comin/_arch.nix {
    inherit pkgs comin;
    inherit (topology) repository;
    inherit (host.services.comin) branch storage;
    hostname = "nixarchserver";
  };
  containerFirewall = pkgs.writeShellScript "nixarchserver-container-firewall" ''
    set -euo pipefail
    export PATH=/usr/bin
    rules=$(mktemp /run/container-firewall.XXXXXXXX)
    trap 'rm -f "$rules"' EXIT
    if nft list table inet infra-container-isolation >/dev/null 2>&1; then
      echo 'delete table inet infra-container-isolation' >> "$rules"
    fi
    cat ${../../archserver/container-isolation.nft} >> "$rules"
    nft -c -f "$rules"
    nft -f "$rules"
  '';
  containerFirewallUnit = pkgs.writeTextDir "nixarchserver-container-firewall.service" ''
    [Unit]
    Description=Isolate container networks from the host
    Before=docker.service

    [Service]
    Type=oneshot
    RemainAfterExit=yes
    ExecStart=${containerFirewall}
    ExecReload=${containerFirewall}

    [Install]
    RequiredBy=docker.service
    WantedBy=multi-user.target
  '';
  units = [
    {
      name = "nixarchserver-awg-service-addresses.service";
      source = awg.serviceAddressesUnit;
    }
    {
      name = "nixarchserver-container-firewall.service";
      source = containerFirewallUnit;
    }
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
  ++ lib.optionals (host.services.opencloud != null) [
    {
      name = "nixarchserver-opencloud.service";
      source = opencloud.unit;
    }
  ]
  ++ lib.optionals (host.services.vaultwarden != null) [
    {
      name = "nixarchserver-vaultwarden.service";
      source = vaultwarden.unit;
    }
  ]
  ++ lib.optionals (host.services.immich != null) [
    {
      name = "nixarchserver-immich.service";
      source = immich.unit;
    }
  ]
  ++ lib.optionals (host.services.inbuxa != null) [
    {
      name = "infra-inbuxa.service";
      source = inbuxaUnit;
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
    trap 'unlink "$directory/immich.env" 2>/dev/null || :; unlink "$directory/webmail-secrets.env" 2>/dev/null || :; unlink "$directory/vaultwarden.env" 2>/dev/null || :; unlink "$directory/authentik.env" 2>/dev/null || :; unlink "$directory/${interface}.conf" 2>/dev/null || :; rmdir "$directory"' EXIT
    ${lib.optionalString (host.services.authentik != null) ''
      ${authentik.command} check "$directory"
    ''}
    ${lib.optionalString (host.services.vaultwarden != null) ''
      ${vaultwarden.prepare} "$directory"
    ''}
    ${lib.optionalString (host.services.inbuxa != null) ''
      ${inbuxaPrepare} "$directory"
    ''}
    ${lib.optionalString (host.services.immich != null) ''
      ${immich.prepare} "$directory"
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
      if [[ $unit = infra-inbuxa.service && -f $path && ! -L $path ]] && cmp -s "$path" ${inbuxaConfig}/infra-inbuxa.service; then
        continue
      fi
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
    install -d "$directory/nixarchserver-awg.service.wants"
    ln -sfn ../nixarchserver-awg-service-addresses.service "$directory/nixarchserver-awg.service.wants/nixarchserver-awg-service-addresses.service"
    install -d "$directory/docker.service.requires"
    ln -sfn ../nixarchserver-container-firewall.service "$directory/docker.service.requires/nixarchserver-container-firewall.service"
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
        nixarchserver-container-firewall.service) systemctl reload-or-restart "$unit" ;;
        ${lib.concatMapStringsSep "|" (unit: unit.name) (builtins.filter (unit: unit.name != "nixarchserver-container-firewall.service") startUnits)}) systemctl restart "$unit" ;;
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
