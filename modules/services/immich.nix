{ delib, ... }:
delib.module {
  name = "infra.services.immich";
  nixos.always.infra.services.immich = {
    inbound.web = { };
    outbound.web = {
      node = "archserver";
      port = 2283;
    };
  };
}
