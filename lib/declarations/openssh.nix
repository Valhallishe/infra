{ delib, ... }:
delib.module {
  name = "infra.security.openssh";
  options = { infra.security.openssh.enable = delib.boolOption true; };
}
