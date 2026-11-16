{ delib, config, ... }:
delib.module {
  name = "infra.services.immich";
  nixos.always.infra.services.immich.routes = [
    {
      domain = "photo.${config.infra.domain}";
      protocol = "https";
      in_port = 443;
      in_node = config.infra.nodes.halo;
      out_port = 2283;
      out_node = config.infra.nodes.archserver;
    }
  ];
}
