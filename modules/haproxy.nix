{
  delib,
  inputs,
  config,
  lib,
  ...
}:
let
  infra = config.infra;
  routes = lib.filter (route: route.protocol != "udp") (
    import (inputs.self + "/lib/gateway-routes.nix") infra
  );
  proxy = import (inputs.self + "/lib/haproxy.nix") {
    inherit lib routes;
    domain = infra.domain;
    certificate = "/var/lib/acme/${infra.domain}/full.pem";
  };
in
delib.module {
  name = "infra.web";
  nixos.ifEnabled = {
    infra.web.enable = true;
    assertions = proxy.assertions;
    networking.domain = infra.domain;
    networking.firewall.allowedTCPPorts = proxy.ports;
    services.haproxy = {
      enable = true;
      config = proxy.config;
    };
    security.acme = {
      acceptTerms = true;
      defaults.email = "admin@${infra.domain}";
      certs.${infra.domain} = {
        extraDomainNames = lib.remove infra.domain proxy.domains;
        listenHTTP = "127.0.0.1:8008";
        group = config.services.haproxy.group;
        # Never fall back to a restart when certificates change.
        postRun = ''
          if ${config.systemd.package}/bin/systemctl is-active --quiet haproxy.service; then
            ${config.systemd.package}/bin/systemctl reload haproxy.service
          fi
        '';
      };
    };
    systemd.services.haproxy = {
      requires = [ "acme-${infra.domain}.service" ];
      after = [ "acme-${infra.domain}.service" ];
    };
  };
}
