{ delib, config, ... }:
delib.module {
  name = "infra.services.vaultwarden";
  nixos.always.infra.services.vaultwarden.routes = [
    {
      domain = "pass.${config.infra.domain}";
      protocol = "https";
      in_port = 443;
      in_node = config.infra.nodes.halo;
      out_port = 6082;
      out_node = config.infra.nodes.archserver;
    }
  ];
}
