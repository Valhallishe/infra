{
  delib,
  config,
  lib,
  ...
}:
let
  infra = config.infra;
  endpoints = import ../../lib/service-endpoints.nix { inherit lib infra; };
  routes = lib.filter (route: route.protocol != "udp") (
    import ../../lib/gateway-routes.nix {
      inherit endpoints;
      routes = infra.hosts.${config.networking.hostName}.gateway.routes or [ ];
    }
  );
  proxy = import ../../lib/haproxy.nix {
    inherit lib routes;
    brand = infra.branding.${infra.hosts.${config.networking.hostName}.branding};
    domain = infra.domain;
    certificate = "/var/lib/acme/${infra.domain}/full.pem";
  };
in
delib.module {
  name = "infra.web";
  options = { infra.web.enable = delib.boolOption false; };

  nixos.always.options.infra.web = {
    enable = lib.mkEnableOption "public web hosting";
    node = lib.mkOption {
      type = lib.types.str;
      default = config.infra.hosts.${config.networking.hostName}.node or config.networking.hostName;
      description = "Overlay node used by this gateway.";
    };
  };

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
