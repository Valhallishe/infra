{ delib, ... }:
delib.module {
  name = "infra.services.peertube";
  nixos.always.infra.services.peertube = {
    inbound.web = { };
    outbound.web = {
      node = "archserver";
      port = 9001;
    };
  };
}
