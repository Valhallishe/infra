{
  config,
  lib,
  pkgs,
  ...
}:
let
  node = config.infra.nodes.${config.infra.awg.node};
  relayConfig = config.infra.hosts.${config.networking.hostName}.services.inbuxaRelay or null;
  port = relayConfig.linkPort;
  stateDir = relayConfig.storage.state.location;
  managedStateDir = lib.hasPrefix "/var/lib/" stateDir;
  binary = pkgs.fetchurl {
    url = "https://git.coffeylabs.org/inbuxa/inbuxa-server/releases/download/v27.1-rc.5/inbuxa-relay-x86_64-linux-musl";
    sha256 = "1c169d75aac1da6c28b4563a2f2680ee1332e202b9ca35c506b33216c67cd71e";
  };
  relay = pkgs.runCommand "inbuxa-relay" { } ''
    install -Dm755 ${binary} $out/bin/inbuxa-relay
  '';
in
{
  config = lib.mkIf (relayConfig != null) {
    users.groups.inbuxa-relay = { };
    users.users.inbuxa-relay = {
      isSystemUser = true;
      group = "inbuxa-relay";
    };
    networking.firewall.allowedTCPPorts = [ 25 ];
    networking.firewall.interfaces.${config.infra.network.interface}.allowedTCPPorts = [ port ];
    systemd.tmpfiles.settings.inbuxa-relay = lib.mkIf (!managedStateDir) {
      ${stateDir}.d = {
        mode = "0700";
        user = "inbuxa-relay";
        group = "inbuxa-relay";
      };
    };
    systemd.services.inbuxa-relay = {
      description = "inbuxa Relay";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network-online.target"
        "wireguard-${config.infra.network.interface}.service"
      ];
      wants = [ "network-online.target" ];
      unitConfig = {
        ConditionPathExists = "${stateDir}/identity.json";
        RequiresMountsFor = lib.mkIf (!managedStateDir) stateDir;
      };
      serviceConfig = {
        ExecStart = "${relay}/bin/inbuxa-relay run --state ${builtins.toJSON stateDir} --link-listen ${node.ip}:${toString port}";
        User = "inbuxa-relay";
        Group = "inbuxa-relay";
        StateDirectory = lib.mkIf managedStateDir (lib.removePrefix "/var/lib/" stateDir);
        ReadWritePaths = lib.mkIf (!managedStateDir) [ stateDir ];
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
