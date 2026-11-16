{ delib, ... }:
delib.module {
  name = "infra.krozzzis";
  options = { infra.krozzzis.enable = delib.boolOption false; };
}
