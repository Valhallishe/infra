{ lib, ... }:
{
  options.services.autopush = import ../../../lib/service-option.nix {
    inherit lib;
  };
}
