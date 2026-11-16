{ delib, config, pkgs, inputs, ... }:
delib.host {
  name = "halo";
  nixos = {
    networking.useDHCP = false;
    networking.useNetworkd = true;
    services.resolved.enable = true;
    services.resolved.settings.Resolve = {
      LLMNR = "no";
      MulticastDNS = "no";
    };
    age.secrets.halo-network = {
      file = (inputs.self + "/secrets/halo-network.age");
      path = "/run/systemd/network/10-wan.network";
      mode = "0644";
    };
    infra.awg.enable = true;
    systemd.services.systemd-networkd.restartTriggers = [ (inputs.self + "/secrets/halo-network.age") ];
  };
}
