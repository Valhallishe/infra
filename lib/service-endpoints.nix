{ lib, infra }:
rec {
  backend =
    target:
    let
      inherit (target) host service flow;
      deployment = infra.hosts.${host} or (throw "Unknown service host: ${host}");
      instance = deployment.services.${service} or null;
      endpoint =
        if instance == null then
          throw "Service ${service} is not declared on ${host}"
        else
          instance.flows.${flow} or (throw "Unknown flow: ${host}.${service}.${flow}");
      node = infra.nodes.${deployment.node};
    in
    endpoint
    // {
      inherit node;
      address = if endpoint.overlay then assert instance.overlayAddress != null; instance.overlayAddress else node.ip;
    };

  httpPorts = {
    http = 80;
    https = 443;
  };

  listener =
    route: endpoint:
    let
      defaultProtocol =
        if builtins.hasAttr endpoint.protocol httpPorts then "https" else endpoint.protocol;
      protocol = lib.defaultTo defaultProtocol route.listen.protocol;
      port = lib.defaultTo (httpPorts.${protocol} or endpoint.port) route.listen.port;
      tls = lib.defaultTo (if protocol == "https" then "terminate" else "none") route.listen.tls;
    in
    {
      inherit protocol port tls;
      inherit (route.listen) acceptProxyProtocol;
    };

  public =
    gateway: target:
    let
      route =
        lib.findSingle (route: route.to == target)
          (throw "Missing public route on ${gateway} for ${target.host}.${target.service}.${target.flow}")
          (throw "Multiple public routes on ${gateway} for ${target.host}.${target.service}.${target.flow}")
          infra.hosts.${gateway}.gateway.routes;
      frontend = listener route (backend target);
      hostname = if route.domain == null then throw "Public HTTP route needs a domain" else route.domain;
      standardPort = httpPorts.${frontend.protocol} or (throw "Expected a public HTTP(S) route");
      authority =
        hostname + lib.optionalString (frontend.port != standardPort) ":${toString frontend.port}";
    in
    {
      inherit hostname authority;
      inherit (frontend) port protocol;
      url = "${frontend.protocol}://${authority}";
    };
}
