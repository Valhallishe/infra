{ delib, ... }:
delib.module {
  name = "infra.security.firewall";
  options = {
    infra.security.firewall.enable = delib.boolOption true;
  };

  nixos.ifEnabled = {
    networking.firewall.enable = true;
    networking.nftables.enable = true;
  };
}
