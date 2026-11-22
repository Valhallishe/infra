{ config, lib, ... }:
{
  options.infra.web = {
    enable = lib.mkEnableOption "public web hosting";
    node = lib.mkOption {
      type = lib.types.str;
      default = config.infra.hosts.${config.networking.hostName}.node or config.networking.hostName;
      description = "Overlay node used by this gateway.";
    };
  };
}
