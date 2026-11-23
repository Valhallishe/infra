{
  pkgs,
  endpoints,
  topology,
  hostname,
}:
let
  host = topology.hosts.${hostname};
  service = host.services.inbuxa;
  brand = topology.branding.${service.branding};
  themes = import ../../branding/_service-themes.nix {
    inherit pkgs;
    inbuxaProfile = brand;
    authentikProfile = topology.branding.${host.services.authentik.branding};
    nextcloudProfile = topology.branding.${host.services.nextcloud.branding};
  };
  theme = pkgs.runCommand "inbuxa-theme" { } ''
    mkdir -p "$out/brand"
    cp ${themes}/inbuxa.css "$out/inbuxa.css"
    cp ${themes}/inbuxa-webmail.conf "$out/webmail.conf"
    cp -rL ${themes}/inbuxa-brand/. "$out/brand/"
    version=$(cd "$out" && sha256sum inbuxa.css webmail.conf brand/* | sha256sum | cut -c1-12)
    sed -i "s|/_infra/theme.css|/_infra/theme.css?v=$version|; s|BRAND_VERSION|$version|" "$out/webmail.conf"
    sed -i "s|brand-light.svg|brand-light.svg?v=$version|; s|brand-dark.svg|brand-dark.svg?v=$version|" "$out/inbuxa.css"
  '';
in
pkgs.runCommand "inbuxa-config" { } ''
  mkdir -p "$out"
  ln -s ${theme} "$out/theme"
  cp ${./nginx.conf} "$out/nginx.conf"
  cp ${./oauth.js} "$out/oauth.js"
''
