{
  pkgs,
  decrypt,
  network,
  node,
  peer,
}:
let
  inherit (pkgs) lib;
  # Keep the legacy ordering so the first-switch preflight can compare files.
  legacyOrder = [
    "Jc"
    "Jmin"
    "Jmax"
    "S1"
    "S2"
    "H1"
    "H2"
    "H3"
    "H4"
  ];
  parameters =
    builtins.filter (name: builtins.hasAttr name network.obfuscation) legacyOrder
    ++ lib.subtractLists legacyOrder (builtins.attrNames network.obfuscation);
  template = pkgs.writeText "archserver-awg.conf" ''
    [Interface]
    Address = ${node.ip}/32
    PrivateKey = @PRIVATE_KEY@
    ${lib.concatMapStringsSep "\n" (
      name: "${name} = ${toString network.obfuscation.${name}}"
    ) parameters}

    [Peer]
    PublicKey = @PEER_PUBLIC_KEY@
    ${
      lib.optionalString (peer.awg.endpoint != null) "Endpoint = ${peer.awg.endpoint}\n"
    }AllowedIPs = ${peer.ip}/32
    PersistentKeepalive = 25
  '';
  prepare = pkgs.writeShellScript "nixarchserver-awg-config" ''
    set -euo pipefail
    umask 077
    private=$(${decrypt node.awg.privateKey})
    public=$(${decrypt peer.awg.publicKey})
    for key in "$private" "$public"; do
      [[ $key =~ ^[A-Za-z0-9+/]{43}=$ ]]
    done
    while IFS= read -r line; do
      line=''${line//@PRIVATE_KEY@/$private}
      printf '%s\n' "''${line//@PEER_PUBLIC_KEY@/$public}"
    done < ${template} > "$1/${network.interface}.conf"
  '';
in
{
  inherit prepare;
  serviceAddressesUnit = pkgs.writeTextDir "nixarchserver-awg-service-addresses.service" ''
    [Unit]
    Description=Add service subnet routes to the AWG overlay
    Requires=nixarchserver-awg.service
    After=nixarchserver-awg.service
    PartOf=nixarchserver-awg.service

    [Service]
    Type=oneshot
    RemainAfterExit=yes
    ExecStart=${pkgs.writeShellScript "archserver-awg-service-addresses" ''
      set -euo pipefail
      /usr/bin/ip address replace ${node.serviceHostIp}/32 dev ${network.interface}
      public=$(${decrypt peer.awg.publicKey})
      /usr/bin/awg set ${network.interface} peer "$public" allowed-ips ${peer.ip}/32,${peer.serviceSubnet}
      /usr/bin/ip route replace ${peer.serviceSubnet} dev ${network.interface}
    ''}

    [Install]
    WantedBy=multi-user.target
  '';
  unit = pkgs.writeTextDir "nixarchserver-awg.service" ''
    [Unit]
    Description=AmneziaWG ${network.interface} (nixarchserver)
    Wants=network-online.target nss-lookup.target
    After=network-online.target nss-lookup.target awg-quick@${network.interface}.service
    Conflicts=awg-quick@${network.interface}.service

    [Service]
    Type=oneshot
    RemainAfterExit=yes
    RuntimeDirectory=nixarchserver-awg
    RuntimeDirectoryMode=0700
    ExecStartPre=${prepare} %t/nixarchserver-awg
    ExecStart=/usr/bin/awg-quick up %t/nixarchserver-awg/${network.interface}.conf
    ExecStop=/usr/bin/awg-quick down %t/nixarchserver-awg/${network.interface}.conf

    [Install]
    WantedBy=multi-user.target
  '';
}
