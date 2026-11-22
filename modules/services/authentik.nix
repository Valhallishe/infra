{ delib, ... }:
delib.module {
  name = "infra.services.authentik";
  nixos.always.infra.services.authentik = {
    inbound.web = { };
    outbound.web = {
      node = "archserver";
      port = 5680;
    };
  };
}
