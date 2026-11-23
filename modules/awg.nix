{
  delib,
  config,
  lib,
  pkgs,
  ...
}:
delib.module {
  name = "infra.awg";
  nixos.always =
    let
      infra = config.infra;
      cfg = infra.awg;
      host = infra.hosts.${config.networking.hostName} or null;
      link = host.services.awg or null;
      network = infra.network;
      node = infra.nodes.${cfg.node};
      peers = lib.genAttrs cfg.peers (name: infra.nodes.${name});
      interface = network.interface;
      secretName = name: "awg-peer-${name}";
      peerSetup = name: peer: ''
        ${pkgs.amneziawg-tools}/bin/awg set ${lib.escapeShellArg interface} peer "$(cat ${
          lib.escapeShellArg config.age.secrets.${secretName name}.path
        })" allowed-ips ${lib.escapeShellArg "${peer.ip}/32"} ${
          lib.optionalString (
            peer.awg.endpoint != null
          ) "endpoint ${lib.escapeShellArg peer.awg.endpoint} persistent-keepalive 25"
        }
        ${pkgs.iproute2}/bin/ip route replace ${lib.escapeShellArg "${peer.ip}/32"} dev ${lib.escapeShellArg interface}
      '';
    in
    {
      options.infra.awg = {
        enable = lib.mkEnableOption "infrastructure AWG overlay" // {
          default = link != null;
        };
        node = lib.mkOption {
          type = lib.types.str;
          default = host.node or config.networking.hostName;
        };
        peers = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default =
            if link != null then
              [ link.peer ]
            else
              lib.filter (name: name != cfg.node) (builtins.attrNames infra.nodes);
          description = "Peer node names, taken from the host inventory when declared.";
        };
      };

      config = lib.mkIf cfg.enable {
        assertions = [
          {
            assertion = !(builtins.elem cfg.node cfg.peers);
            message = "AWG node cannot peer with itself.";
          }
          {
            assertion =
              builtins.length (lib.unique (map (n: n.ip) (builtins.attrValues infra.nodes)))
              == builtins.length (builtins.attrNames infra.nodes);
            message = "Infrastructure nodes must have distinct IP addresses.";
          }
        ];
        age.secrets = {
          awg-private.file = node.awg.privateKey;
        }
        // lib.mapAttrs' (
          name: peer:
          lib.nameValuePair (secretName name) {
            file = peer.awg.publicKey;
          }
        ) peers;
        networking.firewall.allowedUDPPorts = [ network.port ];
        networking.wireguard.useNetworkd = false;
        networking.wireguard.interfaces.${interface} = {
          type = "amneziawg";
          ips = [ "${node.ip}/32" ];
          listenPort = network.port;
          privateKeyFile = config.age.secrets.awg-private.path;
          extraOptions = network.obfuscation;
          postSetup = lib.concatStringsSep "\n" (lib.mapAttrsToList peerSetup peers);
          postShutdown = lib.concatStringsSep "\n" (
            lib.mapAttrsToList (_: peer: ''
              ${pkgs.iproute2}/bin/ip route del ${lib.escapeShellArg "${peer.ip}/32"} dev ${lib.escapeShellArg interface} 2>/dev/null || true
            '') peers
          );
        };
        systemd.services.infra-awg-service-addresses = {
          description = "Add service subnet routes to the AWG overlay";
          wantedBy = [ "multi-user.target" "wireguard-${interface}.service" ];
          requires = [ "wireguard-${interface}.service" ];
          after = [ "wireguard-${interface}.service" ];
          partOf = [ "wireguard-${interface}.service" ];
          path = [ pkgs.iproute2 pkgs.amneziawg-tools ];
          serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
          script = ''
            ip address replace ${lib.escapeShellArg "${node.serviceHostIp}/32"} dev ${lib.escapeShellArg interface}
            ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: peer: ''
              awg set ${lib.escapeShellArg interface} peer "$(cat ${lib.escapeShellArg config.age.secrets.${secretName name}.path})" allowed-ips ${lib.escapeShellArg "${peer.ip}/32,${peer.serviceSubnet}"}
              ip route replace ${lib.escapeShellArg peer.serviceSubnet} dev ${lib.escapeShellArg interface}
            '') peers)}
          '';
        };
        systemd.services."wireguard-${interface}".restartTriggers = [
          node.awg.privateKey
        ]
        ++ map (peer: peer.awg.publicKey) (builtins.attrValues peers);
      };
    };
}
