{ lib, ... }:
{
  options.services.immich = import ../../../lib/service-option.nix {
    inherit lib;
  };
}
