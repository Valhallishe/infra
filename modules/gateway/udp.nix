{
  delib,
  config,
  lib,
  ...
}:
let
  infra = config.infra;
  endpoints = import ../../lib/service-endpoints.nix { inherit lib infra; };
  routes = lib.filter (route: route.protocol == "udp") (
    import ../../lib/gateway-routes.nix {
      inherit endpoints;
      routes = infra.hosts.${config.networking.hostName}.gateway.routes or [ ];
    }
  );
  udp = import ../../lib/udp.nix {
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
