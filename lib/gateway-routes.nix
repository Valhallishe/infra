{
  endpoints,
  routes,
  gateway ? null,
}:
map (
  route:
  let
    backend = endpoints.backend route.to;
    inbound = endpoints.listener route backend;
  in
  {
    inherit (route) domain pathPrefixes;
    inherit (inbound) protocol tls;
    in_port = inbound.port;
    out_port = backend.port;
    out_node = backend.node;
    out_address =
      if route.to.host == gateway && builtins.hasAttr inbound.protocol endpoints.httpPorts then
        "127.0.0.1"
      else
        backend.address;
    out_protocol = if backend.protocol == "https" then "https" else "http";
    proxy_protocol = {
      accept = inbound.acceptProxyProtocol;
      send = backend.proxyProtocol;
    };
  }
) routes
