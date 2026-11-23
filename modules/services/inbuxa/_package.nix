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
  target = name: flow: {
    host = hostname;
    service = name;
    inherit flow;
  };
  backend = flow: endpoints.backend (target "inbuxa" flow);
  public = name: flow: endpoints.public host.publicGateway (target name flow);
  scim = backend "scim";
  webmail = public "inbuxa" "webmail";
  admin = public "inbuxa" "admin";
  sso = public "authentik" "http";
  decrypt = pkgs.writeShellScript "inbuxa-decrypt-secrets" ''
    set -eu
    umask 077
    ${pkgs.age}/bin/age -d -i /etc/ssh/ssh_host_ed25519_key ${../../../secrets/nixarchserver-inbuxa.age} > /run/infra-inbuxa/webmail-secrets.env
  '';
  unit = pkgs.replaceVars ./infra-inbuxa.service.in {
    dataDir = service.storage.project.location;
    inherit decrypt;
  };
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
  # Compose inputs are rendered together with the gateway routes.
  compose = pkgs.replaceVars ./compose.yaml.in {
    oauthMount = builtins.toJSON "${./oauth.js}:/app/server/dist/oauth.js:ro";
    nginxMount = builtins.toJSON "${./nginx.conf}:/etc/nginx/conf.d/default.conf:ro";
    themeMount = builtins.toJSON "${theme}:/etc/nginx/theme:ro";
    configMount = builtins.toJSON "${service.storage.config.location}:/etc/inbuxa";
    mailMount = builtins.toJSON "${service.storage.mail.location}:/var/lib/inbuxa";
    appName = builtins.toJSON "${brand.name} Mail";
    webmailAddress = (backend "webmail").address;
    scimAddress = scim.address;
    scimPort = toString scim.port;
    webmailPort = toString (backend "webmail").port;
    adminAddress = (backend "admin").address;
    adminPort = toString (backend "admin").port;
    webmailUrl = webmail.url;
    adminUrl = admin.url;
    issuer = "${sso.url}/application/o/inbuxa-mail/";
  };
in
pkgs.runCommand "inbuxa-config" { } ''
  mkdir -p "$out"
  cp ${compose} "$out/compose.yaml"
  cp ${./nginx.conf} "$out/nginx.conf"
  cp ${./oauth.js} "$out/oauth.js"
  cp ${unit} "$out/infra-inbuxa.service"
''
