{
  delib,
  inputs,
  config,
  lib,
  ...
}:
let
  infra = config.infra;
  routes = lib.filter (r: r.protocol == "udp" && r.in_node.ip == infra.nodes.${infra.web.node}.ip) (
    lib.concatMap (service: service.routes) (builtins.attrValues infra.services)
  );
  udp = import (inputs.self + "/lib/udp.nix") {
    inherit lib routes;
    interface = infra.network.interface;
    sourceIP = infra.nodes.${infra.web.node}.ip;
  };
in
delib.module {
  name = "infra.web";
  nixos.ifEnabled = lib.mkIf (routes != [ ]) {
    assertions = udp.assertions ++ [
      {
        assertion =
          infra.awg.enable
          && lib.all (
            r: builtins.elem r.out_node.ip (map (name: infra.nodes.${name}.ip) infra.awg.peers)
          ) routes;
        message = "UDP backends must be configured AWG peers of this proxy.";
      }
    ];
    networking.firewall.allowedUDPPorts = udp.ports;
    networking.firewall.filterForward = true;
    boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
    networking.nftables.tables.infra-udp = {
      family = "inet";
      content = udp.content;
    };
  };
}
