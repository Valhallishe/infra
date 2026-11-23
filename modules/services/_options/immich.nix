{ lib, ... }:
{
  options.services.immich = import ../../../lib/service-option.nix {
    inherit lib;
    options.secretFile = lib.mkOption { type = lib.types.path; };
  };
}
