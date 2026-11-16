{ config, ... }:
{
  networking.domain = "valhallishe.net";

  services.caddy.virtualHosts.${config.networking.domain}.extraConfig = ''
    respond "" 200
  '';
}
