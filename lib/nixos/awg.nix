{ config, lib, ... }:
{
  options.infra = {
    awg = {
      enable = lib.mkEnableOption "infrastructure AWG overlay";
      node = lib.mkOption {
        type = lib.types.str;
        default = config.networking.hostName;
      };
      peers = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = lib.filter (name: name != config.infra.awg.node) (builtins.attrNames config.infra.nodes);
        description = "Peer node names; defaults to all other declared nodes.";
      };
    };
  };
}
