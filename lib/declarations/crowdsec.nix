{ delib, ... }:
delib.module {
  name = "infra.security.crowdsec";
  options = { infra.security.crowdsec.enable = delib.boolOption true; };
}
