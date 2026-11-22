{ lib, ... }:
{
  options.services.authentik = import ../../../lib/service-option.nix {
    inherit lib;
    options = {
      branding = lib.mkOption { type = lib.types.str; };
      dataDir = lib.mkOption { type = lib.types.str; };
      database.volume = lib.mkOption { type = lib.types.str; };
      httpsPort = lib.mkOption { type = lib.types.port; };
      secretFile = lib.mkOption { type = lib.types.path; };
    };
  };
}
