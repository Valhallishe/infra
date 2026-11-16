{ ... }:
{
  services.caddy.virtualHosts."sso.valhallishe.net".extraConfig = ''
    reverse_proxy 10.1.0.2:5680
  '';
}
