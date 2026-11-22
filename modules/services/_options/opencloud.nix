{ lib, ... }:
{
  options.services.opencloud = import ../../../lib/service-option.nix {
    inherit lib;
    options = {
      branding = lib.mkOption { type = lib.types.str; };
      storage = lib.mkOption { type = lib.types.str; };
      radicaleStorage = lib.mkOption { type = lib.types.str; };
      mount.path = lib.mkOption { type = lib.types.str; };
      mount.unit = lib.mkOption { type = lib.types.str; };
      mount.uuid = lib.mkOption { type = lib.types.str; };
    };
  };
}
