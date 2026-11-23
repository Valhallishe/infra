{
  pkgs,
  decrypt,
  instance,
  public,
  backend,
  ssoUrl,
}:
let
  dataDir = instance.storage.data.location;
  runtime = "/run/nixarchserver-vaultwarden";
  compose = pkgs.writeText "vaultwarden-compose.json" (builtins.toJSON {
    services.vaultwarden = {
      inherit (instance) image;
      container_name = "vaultwarden";
      restart = "unless-stopped";
      security_opt = [ "no-new-privileges:true" ];
      env_file = [
        {
          path = "${runtime}/vaultwarden.env";
          format = "raw";
        }
      ];
      environment = {
        DOMAIN = public.url;
        SIGNUPS_ALLOWED = "false";
        SSO_ENABLED = "true";
        SSO_ONLY = "true";
        SSO_AUTHORITY = "${ssoUrl}/application/o/vaultwarden/";
        SSO_SCOPES = "email profile offline_access";
        SSO_SIGNUPS_MATCH_EMAIL = "true";
        SSO_ALLOW_UNKNOWN_EMAIL_VERIFICATION = "false";
        SSO_CLIENT_CACHE_EXPIRATION = "0";
        PUSH_ENABLED = "true";
        PUSH_RELAY_URI = "https://api.bitwarden.eu";
        PUSH_IDENTITY_URI = "https://identity.bitwarden.eu";
      };
      ports = [ "${toString backend.port}:80" ];
      volumes = [
        {
          type = "bind";
          source = dataDir;
          target = "/data";
          bind.create_host_path = false;
        }
      ];
    };
  });
  prepare = pkgs.writeShellScript "vaultwarden-prepare" ''
    set -euo pipefail
    umask 077
    ${decrypt instance.secretFile} > "$1/vaultwarden.env"
    test -s ${pkgs.lib.escapeShellArg (dataDir + "/db.sqlite3")}
  '';
  command = pkgs.writeShellScript "vaultwarden-compose" ''
    set -euo pipefail
    exec /usr/bin/docker compose --project-name vaultwarden -f ${compose} "$@"
  '';
in
{
  inherit prepare;
  unit = pkgs.writeTextDir "nixarchserver-vaultwarden.service" ''
    [Unit]
    Description=Vaultwarden on nixarchserver
    Requires=docker.service
    After=docker.service
    RequiresMountsFor=${dataDir}

    [Service]
    Type=oneshot
    RemainAfterExit=yes
    RuntimeDirectory=nixarchserver-vaultwarden
    RuntimeDirectoryMode=0700
    TimeoutStartSec=180
    ExecStartPre=${prepare} %t/nixarchserver-vaultwarden
    ExecStart=${command} up -d --wait --wait-timeout 90
    ExecStop=${command} stop
  '';
}
