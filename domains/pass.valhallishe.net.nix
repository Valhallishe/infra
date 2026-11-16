{ ... }:
{
  services.caddy.virtualHosts."pass.valhallishe.net".extraConfig = ''
    reverse_proxy 10.1.0.2:6082
  '';
}
