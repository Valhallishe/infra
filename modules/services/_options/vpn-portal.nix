{ lib, ... }:
{
  options.services.vpn-portal = import ../../../lib/service-option.nix { inherit lib; };
}
