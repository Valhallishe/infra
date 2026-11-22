{ delib, ... }:
delib.module {
  name = "infra.security.fail2ban";
  options = {
    infra.security.fail2ban.enable = delib.boolOption true;
  };

  nixos.ifEnabled = {
    services.fail2ban.enable = true;
  };
}
