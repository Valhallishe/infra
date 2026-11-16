{
  delib,
  inputs,
  config,
  lib,
  pkgs,
  ...
}:
delib.module {
  name = "infra.security.firewall";
  nixos.ifEnabled = {
    networking.firewall.enable = true;
    networking.nftables.enable = true;
  };
}
