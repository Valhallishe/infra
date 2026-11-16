{
  delib,
  inputs,
  config,
  lib,
  pkgs,
  ...
}:
delib.module {
  name = "infra.security.openssh";
  nixos.ifEnabled = {
    services.openssh = {
      enable = true;
      openFirewall = true;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "no";
        X11Forwarding = false;
      };
    };
  };
}
