{ lib, ... }:
{
  options.services.nextcloud = import ../../../lib/service-option.nix {
    inherit lib;
    options = {
      branding = lib.mkOption { type = lib.types.str; };
    };
  };
}
