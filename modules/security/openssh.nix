{ delib, ... }:
delib.module {
  name = "infra.security.openssh";
  options = {
    infra.security.openssh.enable = delib.boolOption true;
  };

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
