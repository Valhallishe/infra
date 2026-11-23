{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  inherit (config) infra;
  host = config.networking.hostName;
  instance = infra.hosts.${host}.services.autopush or null;
  endpoints = import ../../../lib/service-endpoints.nix { inherit lib infra; };
  public = endpoints.public host {
    inherit host;
    service = "autopush";
    flow = "endpoint";
  };
  redis = config.services.redis.servers.autopush;
  autopush = inputs.nixpkgs-autopush.legacyPackages.${pkgs.stdenv.hostPlatform.system}.autopush-rs;
  db_dsn = "redis+unix://${redis.unixSocket}";
  redisStateDir = "/var/lib/redis-autopush";
  redisLocation = instance.storage.redis.location;
  stateDir = instance.storage.keys.location;
  managedStateDir = lib.hasPrefix "/var/lib/" stateDir;
  keyFile = "${stateDir}/keys.env";
  dependencies = [
    "autopush-keys.service"
    "redis-autopush.service"
  ];
  localService = {
    after = dependencies;
    requires = dependencies;
    serviceConfig = {
      EnvironmentFile = keyFile;
      Group = redis.group;
      IPAddressDeny = "any";
      IPAddressAllow = "localhost";
    };
  };
in
{
  config = lib.mkIf (instance != null) {
    services.redis.servers.autopush = {
      enable = true;
      appendOnly = true;
    };

    systemd.services.redis-autopush = lib.mkIf (redisLocation != redisStateDir) {
      unitConfig.RequiresMountsFor = redisLocation;
      serviceConfig.BindPaths = [ "${redisLocation}:${redisStateDir}" ];
    };
    systemd.tmpfiles.settings.autopush = lib.mkIf (!managedStateDir) {
      ${stateDir}.d = {
        mode = "0700";
        user = "root";
        group = "root";
      };
    };

    systemd.services.autopush-keys = {
      description = "Initialize Mozilla Autopush keys";
      path = [
        pkgs.coreutils
        pkgs.openssl
      ];
      unitConfig.RequiresMountsFor = lib.mkIf (!managedStateDir) stateDir;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        StateDirectory = lib.mkIf managedStateDir (lib.removePrefix "/var/lib/" stateDir);
        StateDirectoryMode = "0700";
        UMask = "0077";
      };
      script = ''
        set -o pipefail
        if [ -s ${lib.escapeShellArg keyFile} ]; then
          exit 0
        fi
        tmp=$(mktemp ${lib.escapeShellArg "${stateDir}/keys.XXXXXXXX"})
        trap 'rm -f "$tmp"' EXIT
        fernet=$(openssl rand -base64 32 | tr '/+' '_-')
        auth=$(openssl rand -base64 32 | tr '/+' '_-')
        printf 'AUTOCONNECT__CRYPTO_KEYS=[%s]\nAUTOEND__CRYPTO_KEYS=[%s]\nAUTOEND__AUTH_KEYS=[%s]\n' "$fernet" "$fernet" "$auth" > "$tmp"
        mv "$tmp" ${lib.escapeShellArg keyFile}
      '';
    };

    system.services.autopush-autoconnect = {
      imports = [ autopush.services.autoconnect ];
      autoconnect.settings = {
        inherit db_dsn;
        disable_sentry = true;
        port = instance.flows.connect.port;
        router_hostname = "127.0.0.1";
        router_port = 8281;
        endpoint_hostname = public.hostname;
        endpoint_port = public.port;
        endpoint_scheme = public.protocol;
      };
      systemd.service = localService;
    };

    system.services.autopush-autoendpoint = {
      imports = [ autopush.services.autoendpoint ];
      autoendpoint.settings = {
        inherit db_dsn;
        disable_sentry = true;
        host = "127.0.0.1";
        port = instance.flows.endpoint.port;
        endpoint_url = public.url;
      };
      systemd.service = localService;
    };
  };
}
