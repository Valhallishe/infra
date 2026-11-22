{
  config,
  lib,
  inputs,
  ...
}:
let
  profile = config.infra.hosts.${config.networking.hostName}.branding or null;
in
{
  imports = [ inputs.stylix.nixosModules.stylix ];
  config = lib.mkIf (profile != null) {
    stylix = {
      enable = true;
      autoEnable = false;
      polarity = "dark";
      base16Scheme = config.infra.branding.${profile}.dark;
    };
  };
}
