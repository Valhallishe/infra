{
  delib,
  inputs,
  config,
  lib,
  pkgs,
  ...
}:
delib.module {
  name = "infra.security.fail2ban";
  nixos.ifEnabled = {
    services.fail2ban.enable = true;
  };
}
