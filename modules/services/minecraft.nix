{ delib, ... }:
delib.module {
  name = "infra.services.minecraft";
  nixos.always.infra.services.minecraft = {
    inbound.tcp = {
      protocol = "tcp";
      port = 25565;
    };
    outbound.tcp = {
      node = "archserver";
      port = 25565;
      proxyProtocol = "v2";
    };
    inbound.udp = {
      protocol = "udp";
      port = 25565;
    };
    outbound.udp = {
      node = "archserver";
      port = 25565;
    };
  };
}
