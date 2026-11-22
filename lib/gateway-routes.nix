{ endpoints, routes }:
map (
  route:
  let
    backend = endpoints.backend route.to;
    inbound = endpoints.listener route backend;
  in
  {
    inherit (route) domain;
    inherit (inbound) protocol tls;
    in_port = inbound.port;
    out_port = backend.port;
    out_node = backend.node;
    out_protocol = if backend.protocol == "https" then "https" else "http";
    proxy_protocol = {
      accept = inbound.acceptProxyProtocol;
      send = backend.proxyProtocol;
    };
  }
) routes
