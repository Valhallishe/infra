{ lib, ... }:
{
  options.services.inbuxa = import ../../../lib/service-option.nix {
    inherit lib;
    options = {
      branding = lib.mkOption { type = lib.types.str; };
      dataDir = lib.mkOption { type = lib.types.str; };
    };
  };
}
