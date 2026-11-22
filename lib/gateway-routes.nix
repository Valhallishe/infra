infra:
map (
  route:
  let
    service = infra.services.${route.service} or (throw "Unknown gateway service: ${route.service}");
    inbound =
      service.inbound.${route.inbound}
        or (throw "Unknown inbound flow: ${route.service}.${route.inbound}");
    outbound =
      service.outbound.${route.outbound}
        or (throw "Unknown outbound flow: ${route.service}.${route.outbound}");
  in
  {
    inherit (route) domain;
    inherit (inbound) protocol tls;
    in_port = inbound.port;
    out_port = outbound.port;
    out_node = infra.nodes.${outbound.node};
    out_protocol = outbound.protocol;
    proxy_protocol = {
      accept = inbound.acceptProxyProtocol;
      send = outbound.proxyProtocol;
    };
  }
) infra.web.routes
