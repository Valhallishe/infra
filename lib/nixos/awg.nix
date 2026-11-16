{ config, lib, ... }:
{
  options.infra = {
    network = {
      subnet = lib.mkOption { type = lib.types.str; description = "IPv4 CIDR for the infrastructure overlay."; };
      port = lib.mkOption { type = lib.types.port; default = 51825; };
      interface = lib.mkOption { type = lib.types.strMatching "[a-zA-Z0-9_-]{1,15}"; default = "infra0"; };
      obfuscation = lib.mkOption {
        type = lib.types.attrsOf lib.types.int;
        default = { Jc = 4; Jmin = 40; Jmax = 70; S1 = 37; S2 = 73;
          H1 = 52194021; H2 = 52194022; H3 = 52194023; H4 = 52194024; };
      };
    };
    awg = {
      enable = lib.mkEnableOption "infrastructure AWG overlay";
      node = lib.mkOption { type = lib.types.str; default = config.networking.hostName; };
      peers = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = lib.filter (name: name != config.infra.awg.node) (builtins.attrNames config.infra.nodes);
        description = "Peer node names; defaults to all other declared nodes.";
      };
    };
  };
}
