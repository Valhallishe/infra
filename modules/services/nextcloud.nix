{ delib, ... }:
delib.module {
  name = "infra.services.nextcloud";
  nixos.always.infra.services.nextcloud = {
    inbound.web = { };
    outbound.web = {
      node = "archserver";
      port = 6084;
    };
  };
}
