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
  unit = pkgs.replaceVars ./infra-inbuxa.service.in { inherit (service) dataDir; };
  # Compose inputs are rendered together with the gateway routes.
  compose = pkgs.replaceVars ./compose.yaml.in {
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
