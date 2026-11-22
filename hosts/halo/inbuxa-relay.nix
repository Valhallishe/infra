{ delib, pkgs, ... }:
let
  binary = pkgs.fetchurl {
    url = "https://git.coffeylabs.org/inbuxa/inbuxa-server/releases/download/v27.1-rc.5/inbuxa-relay-x86_64-linux-musl";
    sha256 = "1c169d75aac1da6c28b4563a2f2680ee1332e202b9ca35c506b33216c67cd71e";
  };
  relay = pkgs.runCommand "inbuxa-relay" { } ''
    install -Dm755 ${binary} $out/bin/inbuxa-relay
  '';
in
delib.host {
  name = "halo";
  nixos = {
    users.groups.inbuxa-relay = { };
    users.users.inbuxa-relay = {
      isSystemUser = true;
      group = "inbuxa-relay";
    };
    networking.firewall.allowedTCPPorts = [ 25 ];
    networking.firewall.interfaces.infra0.allowedTCPPorts = [ 10443 ];
    systemd.services.inbuxa-relay = {
      description = "inbuxa Relay";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" "wireguard-infra0.service" ];
      wants = [ "network-online.target" ];
      unitConfig.ConditionPathExists = "/var/lib/inbuxa-relay/identity.json";
      serviceConfig = {
        ExecStart = "${relay}/bin/inbuxa-relay run --state /var/lib/inbuxa-relay --link-listen 10.1.0.1:10443";
        User = "inbuxa-relay";
        Group = "inbuxa-relay";
        StateDirectory = "inbuxa-relay";
        StateDirectoryMode = "0700";
        Restart = "always";
        RestartSec = 2;
        AmbientCapabilities = "CAP_NET_BIND_SERVICE";
        CapabilityBoundingSet = "CAP_NET_BIND_SERVICE";
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        LimitNOFILE = 65536;
      };
    };
  };
}
