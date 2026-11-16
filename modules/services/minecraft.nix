{ delib, config, ... }:
delib.module {
  name = "infra.services.minecraft";
  nixos.always.infra.services.minecraft.routes = [
    {
      domain = "mc.play.${config.infra.domain}";
      protocol = "tcp";
      tls = "none";
      in_port = 25565;
      in_node = config.infra.nodes.halo;
      out_port = 25565;
      out_node = config.infra.nodes.archserver;
      proxy_protocol.send = "v2";
    }
    {
      domain = "mc.play.${config.infra.domain}";
      protocol = "udp";
      in_port = 25565;
      in_node = config.infra.nodes.halo;
      out_port = 25565;
      out_node = config.infra.nodes.archserver;
    }
  ];
}
