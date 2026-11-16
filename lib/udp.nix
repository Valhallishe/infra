{
  lib,
  routes,
  interface,
  sourceIP,
}:
{
  assertions = [
    {
      assertion = lib.all (
        r:
        r.tls == "none"
        && !r.proxy_protocol.accept
        && r.proxy_protocol.send == "none"
        && r.out_protocol == "http"
        && !(lib.hasInfix ":" r.out_node.ip)
        && r.out_node.ip != sourceIP
      ) routes;
      message = "UDP routes require distinct IPv4 backends and no TLS or PROXY protocol.";
    }
    {
      assertion = builtins.length (lib.unique (map (r: r.in_port) routes)) == builtins.length routes;
      message = "Each UDP route must have its own incoming port.";
    }
  ];
  ports = lib.unique (map (r: r.in_port) routes);
  content = ''
    chain prerouting {
      type nat hook prerouting priority dstnat; policy accept;
      ${lib.concatMapStringsSep "\n" (r: ''
        iifname != "${interface}" fib daddr type local udp dport ${toString r.in_port} dnat ip to ${r.out_node.ip}:${toString r.out_port}
      '') routes}
    }
    chain postrouting {
      type nat hook postrouting priority srcnat; policy accept;
      ${lib.concatMapStringsSep "\n" (r: ''
        oifname "${interface}" ct status dnat ct original proto-dst ${toString r.in_port} ip daddr ${r.out_node.ip} udp dport ${toString r.out_port} snat ip to ${sourceIP}
      '') routes}
    }
  '';
}
