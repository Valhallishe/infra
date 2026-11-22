{ pkgs, decrypt, instance, public, backend, ssoUrl, brand }:
let
  inherit (pkgs) lib;
  inherit (instance) storage radicaleStorage mount;
  pluginTar = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/kja999/opencloud-radicale-web-apps/3257f2ded2cef102a02b6680f57ef126eb8a34ee/web-app-radicale.tar.gz";
    hash = "sha256-SZcAkgnZRte3fSGtAhBXgLRfzYis4h8eLY7RHKr1CDU=";
  };
  apps = pkgs.runCommand "opencloud-apps" { } ''
    mkdir -p "$out/web-app-radicale"
    tar xzf ${pluginTar} -C "$out/web-app-radicale" --no-xattrs
  '';
  defaultTheme = builtins.fromJSON (builtins.readFile ./theme.json);
  themed = defaultTheme // {
    common = defaultTheme.common // { name = brand.name; slogan = "${brand.name} Files"; logo = "themes/opencloud/assets/logo.svg"; };
    clients = defaultTheme.clients // {
      web = defaultTheme.clients.web // {
        defaults = defaultTheme.clients.web.defaults // {
          logo = "themes/opencloud/assets/logo.svg";
          logoMobile = "themes/opencloud/assets/symbol.svg";
          favicon = "themes/opencloud/assets/symbol.svg";
        };
        themes = map (t: let c = if t.isDark then brand.dark else brand.light; in t // {
          designTokens = t.designTokens // {
            roles = t.designTokens.roles // {
              primary = "#${c.base0D}";
              onPrimary = "#${c.base00}";
              background = "#${c.base00}";
              onBackground = "#${c.base05}";
            };
          };
        }) defaultTheme.clients.web.themes;
      };
    };
  };
  theme = pkgs.runCommand "opencloud-theme" { } ''
    mkdir -p "$out/opencloud/assets"
    cp ${brand.wordmark} "$out/opencloud/assets/logo.svg"
    cp ${brand.symbol} "$out/opencloud/assets/symbol.svg"
    cp ${pkgs.writeText "theme.json" (builtins.toJSON themed)} "$out/opencloud/theme.json"
  '';
  proxy = pkgs.writeText "opencloud-proxy.yaml" (builtins.toJSON {
    additional_policies = [{ name = "default"; routes = map (route: {
      endpoint = route.endpoint;
      backend = "http://radicale:5232";
      remote_user_header = "X-Remote-User";
      skip_x_access_token = true;
      additional_headers = [ { X-Script-Name = "/${route.prefix}"; } ];
    }) [
      { endpoint = "/caldav/"; prefix = "caldav"; }
      { endpoint = "/carddav/"; prefix = "carddav"; }
      { endpoint = "/.well-known/caldav"; prefix = "caldav"; }
      { endpoint = "/.well-known/carddav"; prefix = "carddav"; }
    ]; }];
  });
  radicaleConfig = pkgs.writeText "radicale-config" ''
    [server]
    hosts = 0.0.0.0:5232
    [auth]
    type = http_x_remote_user
    [rights]
    type = owner_only
    [storage]
    filesystem_folder = /var/lib/radicale/collections
    predefined_collections = {"def-addressbook":{"D:displayname":"Contacts","tag":"VADDRESSBOOK"},"def-calendar":{"C:supported-calendar-component-set":"VEVENT,VJOURNAL,VTODO","D:displayname":"Calendar","tag":"VCALENDAR"}}
    [web]
    type = none
  '';
  compose = pkgs.writeText "opencloud-compose.json" (builtins.toJSON {
    services = {
      opencloud = {
        image = "opencloudeu/opencloud-rolling:9.2.0@sha256:99698aea6bd88cf28004c773941cf69e2d24da136a3a45f9819b90b60506d14d";
        user = "1000:1000";
        ports = [ "${backend.address}:${toString backend.port}:9200" ];
        command = [ "server" ];
        environment = {
          OC_URL = public.url;
          PROXY_TLS = "false";
          OC_OIDC_ISSUER = "${ssoUrl}/application/o/opencloud/";
          OC_EXCLUDE_RUN_SERVICES = "idp";
          IDM_CREATE_DEMO_USERS = "false";
          PROXY_AUTOPROVISION_ACCOUNTS = "true";
          PROXY_AUTOPROVISION_CLAIM_USERNAME = "sub";
          PROXY_USER_OIDC_CLAIM = "sub";
          PROXY_USER_CS3_CLAIM = "username";
          PROXY_OIDC_REWRITE_WELLKNOWN = "true";
          GRAPH_USERNAME_MATCH = "none";
          OC_OIDC_CLIENT_ID = "valhallishe-opencloud";
          WEB_OIDC_CLIENT_ID = "valhallishe-opencloud";
          WEBFINGER_WEB_OIDC_CLIENT_ID = "valhallishe-opencloud";
          WEBFINGER_DESKTOP_OIDC_CLIENT_ID = "valhallishe-opencloud";
          WEBFINGER_ANDROID_OIDC_CLIENT_ID = "valhallishe-opencloud";
          WEBFINGER_IOS_OIDC_CLIENT_ID = "valhallishe-opencloud";
          WEB_ASSET_THEMES_PATH = "/opt/branding";
          WEB_UI_THEME_PATH = "/themes/opencloud/theme.json";
        };
        volumes = [
          "/run/nixarchserver-opencloud/opencloud.yaml:/etc/opencloud/opencloud.yaml:ro"
          "${storage}/data:/var/lib/opencloud"
          "${proxy}:/etc/opencloud/proxy.yaml:ro"
          "${apps}:/var/lib/opencloud/web/assets/apps:ro"
          "${theme}:/opt/branding:ro"
        ];
        depends_on = [ "radicale" ];
        restart = "unless-stopped";
      };
      radicale = {
        image = "opencloudeu/radicale:3.5.6@sha256:26047f5279cad5e02be725b2f7131043f77cc2a71e855021f347ba718f11e5be";
        user = "1000:1000";
        volumes = [ "${radicaleStorage}:/var/lib/radicale" "${radicaleConfig}:/etc/radicale/config:ro" ];
        restart = "unless-stopped";
      };
    };
  });
  oidc = pkgs.writeText "opencloud-authentik.py" ''
    url = ${builtins.toJSON public.url}
    ${builtins.readFile ./oidc.py}
  '';
  run = pkgs.writeShellScript "opencloud-compose" ''
    set -euo pipefail
    export PATH=/usr/bin
    if [[ $1 == up ]]; then
      test "$(findmnt -n -o UUID --mountpoint ${lib.escapeShellArg mount.path})" = ${lib.escapeShellArg mount.uuid}
      install -d -m 0750 -o 1000 -g 1000 ${lib.escapeShellArgs [ "${storage}/config" "${storage}/data" radicaleStorage ]}
      ${decrypt ../../../secrets/nixarchserver-opencloud.age} > /run/nixarchserver-opencloud/opencloud.yaml
      chown 1000:1000 /run/nixarchserver-opencloud/opencloud.yaml
      chmod 0600 /run/nixarchserver-opencloud/opencloud.yaml
      docker exec -i authentik-worker-1 ak shell --no-imports < ${oidc}
    fi
    exec docker compose -p nixarchserver-opencloud -f ${compose} "$@"
  '';
in {
  unit = pkgs.writeTextDir "nixarchserver-opencloud.service" ''
    [Unit]
    Description=OpenCloud and private Radicale
    Requires=docker.service nixarchserver-awg.service nixarchserver-authentik.service
    After=docker.service nixarchserver-awg.service nixarchserver-authentik.service
    RequiresMountsFor=${storage} ${radicaleStorage}
    BindsTo=${mount.unit}
    After=${mount.unit}
    [Service]
    Type=oneshot
    RemainAfterExit=yes
    RuntimeDirectory=nixarchserver-opencloud
    RuntimeDirectoryMode=0700
    ExecStart=${run} up -d
    ExecStartPost=/usr/bin/curl --fail --silent --retry 30 --retry-delay 2 --retry-all-errors --max-time 5 -H "Host: ${public.authority}" http://${backend.address}:${toString backend.port}/config.json
    ExecStop=${run} stop
    TimeoutStartSec=600
    [Install]
    WantedBy=multi-user.target
  '';
}
