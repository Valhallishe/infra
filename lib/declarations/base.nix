{ delib, ... }:
delib.module {
  name = "infra.base";
  options = { infra.base.enable = delib.boolOption true; };
}
