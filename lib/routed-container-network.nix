{ pkgs, name, serviceAddress, gatewaySources, awgInterface, uplinkInterface, linkSubnet, ports, httpsEgress ? false, tcpToAwgPeers ? [ ] }:
let
  inherit (pkgs) lib;
  hostIf = "svc-${name}";
  peerIf = "peer-${name}";
  table = "svc_${name}";
  portSet = lib.concatMapStringsSep ", " toString ports;
  sources = lib.concatStringsSep ", " gatewaySources;
  rules = pkgs.writeText "${name}-routed-nftables.conf" ''
    table inet ${table} {
      chain input {
        type filter hook input priority -30; policy accept;
        iifname "${hostIf}" counter drop
      }
      chain output {
        type filter hook output priority -30; policy accept;
        oifname "${hostIf}" counter drop
      }
      chain forward {
        type filter hook forward priority -30; policy accept;
        iifname "${hostIf}" ip saddr != ${serviceAddress} counter drop
        iifname "${hostIf}" ct state established,related accept
        iifname "${uplinkInterface}" oifname "${hostIf}" ip daddr ${serviceAddress} ct state established,related accept
        iifname "${awgInterface}" oifname "${hostIf}" ip saddr { ${sources} } ip daddr ${serviceAddress} tcp dport { ${portSet} } accept${lib.concatMapStrings (peer:
          "\n        iifname \"${hostIf}\" oifname \"${awgInterface}\" ip daddr ${peer.address} tcp dport ${toString peer.port} accept"
          + "\n        iifname \"${awgInterface}\" oifname \"${hostIf}\" ip saddr ${peer.address} ip daddr ${serviceAddress} ct state established,related accept"
        ) tcpToAwgPeers}
        ${lib.optionalString httpsEgress ''
        iifname "${hostIf}" ip daddr { 10.0.0.0/8, 127.0.0.0/8, 169.254.0.0/16, 172.16.0.0/12, 192.168.0.0/16 } drop
        iifname "${hostIf}" oifname "${uplinkInterface}" tcp dport 443 accept
        iifname "${hostIf}" oifname "${uplinkInterface}" ip daddr 1.1.1.1 tcp dport 53 accept
        iifname "${hostIf}" oifname "${uplinkInterface}" ip daddr 1.1.1.1 udp dport 53 accept
        ''}
        iifname "${hostIf}" counter drop
        oifname "${hostIf}" counter drop
      }
      chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        ${lib.optionalString httpsEgress ''ip saddr ${serviceAddress} oifname "${uplinkInterface}" masquerade''}
      }
    }
  '';
  down = pkgs.writeShellScript "${name}-routed-network-down" ''
    set -eu
    export PATH=/usr/bin
    ip link del ${hostIf} 2>/dev/null || :
    nft delete table inet ${table} 2>/dev/null || :
  '';
  up = pkgs.writeShellScript "${name}-routed-network-up" ''
    set -euo pipefail
    export PATH=/usr/bin
    pid="''${1:?container PID required}"
    [[ "$pid" =~ ^[1-9][0-9]*$ ]]
    test -e "/proc/$pid/ns/net"
    ! ip link show ${hostIf} >/dev/null 2>&1
    ! nft list table inet ${table} >/dev/null 2>&1
    nft -c -f ${rules}
    nft -f ${rules}
    trap '${down}' ERR
    ip link add ${hostIf} type veth peer name ${peerIf}
    ip link set ${peerIf} netns "$pid"
    ip addr add ${linkSubnet}.1/30 dev ${hostIf}
    ip link set ${hostIf} up
    nsenter -t "$pid" -n ip link set ${peerIf} name eth0
    nsenter -t "$pid" -n ip addr add ${linkSubnet}.2/30 dev eth0
    nsenter -t "$pid" -n ip addr add ${serviceAddress}/32 dev eth0
    nsenter -t "$pid" -n ip link set eth0 up
    nsenter -t "$pid" -n ip route add default via ${linkSubnet}.1 src ${serviceAddress}
    ip route add ${serviceAddress}/32 dev ${hostIf}
    trap - ERR
  '';
in
pkgs.runCommand "${name}-routed-network" { } ''
  mkdir -p "$out/bin"
  ln -s ${up} "$out/bin/up"
  ln -s ${down} "$out/bin/down"
  ln -s ${rules} "$out/nftables.conf"
''
