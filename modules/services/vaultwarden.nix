{ lib, ... }:
{
  options.services.vaultwarden = import ../../lib/service-option.nix {
    inherit lib;
  };
}
