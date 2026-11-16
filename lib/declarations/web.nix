{ delib, ... }:
delib.module {
  name = "infra.web";
  options = { infra.web.enable = delib.boolOption false; };
}
