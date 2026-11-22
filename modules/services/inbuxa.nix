{ delib, ... }:
delib.module {
  name = "infra.services.inbuxa";
  nixos.always.infra.services.inbuxa = {
    inbound.webmail = { };
    outbound.webmail = {
      node = "archserver";
      port = 18084;
    };
    inbound.admin = { };
    outbound.admin = {
      node = "archserver";
      port = 18081;
    };
  };
}
