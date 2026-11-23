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
  # Compose inputs are rendered together with the gateway routes.
  compose = pkgs.replaceVars ./compose.yaml.in {
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
