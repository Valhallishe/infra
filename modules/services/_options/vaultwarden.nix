{ lib, ... }:
{
  options.services.vaultwarden = import ../../../lib/service-option.nix {
    inherit lib;
    options = {
      image = lib.mkOption { type = lib.types.str; };
      secretFile = lib.mkOption { type = lib.types.path; };
    };
  };
}
