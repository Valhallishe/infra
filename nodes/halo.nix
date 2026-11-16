{ config, ... }:
{
  infra.nodes.halo = {
    hostId = 1;
    awg.endpoint = "net.${config.infra.domain}:${toString config.infra.network.port}";
  };
}
