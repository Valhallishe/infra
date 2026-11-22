{ lib, ... }:
{
  options.services.minecraft = import ../../../lib/service-option.nix {
    inherit lib;
  };
}
