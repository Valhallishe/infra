{ lib, ... }:
{
  options.services.inbuxaRelay = import ../../../lib/service-option.nix {
    inherit lib;
    options = {
      linkPort = lib.mkOption { type = lib.types.port; };
    };
  };
}
