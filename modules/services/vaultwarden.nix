{ delib, ... }:
delib.module {
  name = "infra.services.vaultwarden";
  nixos.always.infra.services.vaultwarden = {
    inbound.web = { };
    outbound.web = {
      node = "archserver";
      port = 6082;
    };
  };
}
