{ delib, config, ... }:
delib.module {
  name = "infra.services.authentik";
  nixos.always.infra.services.authentik.routes = [
    {
      domain = "sso.${config.infra.domain}";
      protocol = "https";
      in_port = 443;
      in_node = config.infra.nodes.halo;
      out_port = 5680;
      out_node = config.infra.nodes.archserver;
    }
  ];
}
