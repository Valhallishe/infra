{ lib, ... }:
{
  options.services.comin = import ../../lib/service-option.nix {
    inherit lib;
    options.branch = lib.mkOption { type = lib.types.str; };
  };
}
