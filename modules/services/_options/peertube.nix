{ lib, ... }:
{
  options.services.peertube = import ../../../lib/service-option.nix {
    inherit lib;
    options = {
      branding = lib.mkOption { type = lib.types.str; };
      adminEmail = lib.mkOption { type = lib.types.str; };
      secretFile = lib.mkOption { type = lib.types.path; };
    };
  };
}
