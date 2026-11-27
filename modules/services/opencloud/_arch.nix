{ pkgs, decrypt, instance, public, ssoUrl, brand, network, home, execAuthentik }:
let
  inherit (pkgs) lib;
  inherit (instance) storage;
  dataDir = storage.data.location;
  radicaleDir = storage.radicale.location;
  filesDir = storage.files.location;
  separateFiles = filesDir != "${dataDir}/storage/users";
  runtime = "/run/nixarchserver-opencloud";
  directories = [ dataDir radicaleDir filesDir ];
  mounts = import ../../../lib/storage-mounts.nix { inherit lib; } (
    [ storage.data storage.radicale ] ++ lib.optional separateFiles storage.files
  );
  pluginTar = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/kja999/opencloud-radicale-web-apps/3257f2ded2cef102a02b6680f57ef126eb8a34ee/web-app-radicale.tar.gz";
    hash = "sha256-SZcAkgnZRte3fSGtAhBXgLRfzYis4h8eLY7RHKr1CDU=";
  };
  model3d = pkgs.fetchurl {
    url = "https://github.com/LetsDrinkSomeTea/opencloud-3dviewer/releases/download/v1.1.0-20260723-124242/3dviewer.zip";
    hash = "sha256-Uop9qOwBRdeDAZhXst5r98HQzRIQpbQ3xaN/cLO2i7w=";
  };
  unzipApp = pkgs.fetchurl {
    url = "https://github.com/opencloud-eu/web-extensions/releases/download/unzip-v2.2.3/unzip-2.2.3.zip";
    hash = "sha256-l9fzZTKUVLOle6OoiSJvko3X+082Hp4Ir8LOvMzGZOs=";
  };
  apps = pkgs.runCommand "opencloud-apps" { nativeBuildInputs = [ pkgs.unzip ]; } ''
    mkdir -p "$out/web-app-radicale"
    tar xzf ${pluginTar} -C "$out/web-app-radicale" --no-xattrs
    ${lib.optionalString instance.apps.model3d "unzip -q ${model3d} -d $out"}
    ${lib.optionalString instance.apps.unzip "unzip -q ${unzipApp} -d $out"}
  '';
  appsConfig = pkgs.writeText "opencloud-apps.yaml" (builtins.toJSON {
    # Unzip converts this string to JavaScript Infinity before comparing sizes.
    unzip.config.maxArchiveSize = "Infinity";
  });
  wordmark = color: pkgs.writeText "opencloud-logo.svg" (lib.replaceStrings
    [ "#ffab65" "0 0 600 295" ''x="203" y="0" width="194" height="192"'' ''x="300" y="265" text-anchor="middle"'' ''font-size="47"'' ''letter-spacing="7"'' ]
    [ color "0 0 420 80" ''x="0" y="0" width="80" height="80"'' ''x="94" y="54"'' ''font-size="38"'' ''letter-spacing="3"'' ]
    (builtins.readFile brand.wordmark));
  symbol = color: pkgs.writeText "opencloud-symbol.svg" (lib.replaceStrings [ "#ffab65" ] [ color ] (builtins.readFile brand.symbol));
  defaultTheme = builtins.fromJSON (builtins.readFile ./theme.json);
  themed = defaultTheme // {
    common = defaultTheme.common // { name = brand.name; slogan = "${brand.name} Files"; logo = "themes/opencloud/assets/valhallishe-logo.svg"; };
    clients = defaultTheme.clients // {
      web = defaultTheme.clients.web // {
        defaults = defaultTheme.clients.web.defaults // {
          logo = "themes/opencloud/assets/valhallishe-logo.svg";
          logoMobile = "themes/opencloud/assets/valhallishe-symbol.svg";
          favicon = "themes/opencloud/assets/valhallishe-symbol.svg";
        };
        themes = map (t: let c = if t.isDark then brand.dark else brand.light; in t // {
          logo = if t.isDark then "themes/opencloud/assets/valhallishe-logo.svg" else "themes/opencloud/assets/valhallishe-logo-light.svg";
          logoMobile = if t.isDark then "themes/opencloud/assets/valhallishe-symbol.svg" else "themes/opencloud/assets/valhallishe-symbol-light.svg";
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
    cp ${wordmark "#${brand.dark.base0D}"} "$out/opencloud/assets/valhallishe-logo.svg"
    cp ${wordmark "#${brand.light.base0D}"} "$out/opencloud/assets/valhallishe-logo-light.svg"
    cp ${symbol "#${brand.dark.base0D}"} "$out/opencloud/assets/valhallishe-symbol.svg"
    cp ${symbol "#${brand.light.base0D}"} "$out/opencloud/assets/valhallishe-symbol-light.svg"
    cp ${pkgs.writeText "theme.json" (builtins.toJSON themed)} "$out/opencloud/valhallishe.json"
  '';
  proxy = pkgs.writeText "opencloud-proxy.yaml" (builtins.toJSON {
    additional_policies = [{ name = "default"; routes = map (route: {
      endpoint = route.endpoint;
      backend = "http://127.0.0.1:5232";
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
  csp = pkgs.writeText "opencloud-csp.yaml" (builtins.toJSON {
    directives = {
      default-src = [ "'none'" ];
      child-src = [ "'self'" ];
      connect-src = [ "'self'" "blob:" ssoUrl "https://raw.githubusercontent.com/opencloud-eu/awesome-apps/" "https://update.opencloud.eu/" ];
      font-src = [ "'self'" ];
      frame-ancestors = [ "'self'" ];
      frame-src = [ "'self'" "blob:" ssoUrl "https://embed.diagrams.net/" ];
      img-src = [ "'self'" "data:" "blob:" "https://raw.githubusercontent.com/opencloud-eu/awesome-apps/" ];
      manifest-src = [ "'self'" ];
      media-src = [ "'self'" "blob:" ];
      object-src = [ "'self'" "blob:" ];
      script-src = [ "'self'" "'unsafe-inline'" ];
      style-src = [ "'self'" "'unsafe-inline'" "blob:" ];
    };
  });
  radicaleConfig = pkgs.writeText "radicale-config" ''
    [server]
    hosts = 127.0.0.1:5232
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
  welcome = pkgs.runCommand "opencloud-welcome" { } ''
    mkdir -p "$out"
    cp ${pkgs.replaceVars ./welcome.html { issuer = "${ssoUrl}/application/o/opencloud/"; }} "$out/index.html"
  '';
  nginx = pkgs.writeText "opencloud-nginx.conf" ''
    pid /tmp/nginx.pid;
    events {}
    http {
      client_body_temp_path /tmp/nginx-client;
      proxy_temp_path /tmp/nginx-proxy;
      fastcgi_temp_path /tmp/nginx-fastcgi;
      uwsgi_temp_path /tmp/nginx-uwsgi;
      scgi_temp_path /tmp/nginx-scgi;
      server {
        listen 80;
        client_max_body_size 0;
        proxy_request_buffering off;
        proxy_buffering off;
        proxy_read_timeout 3600s;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Forwarded-Host $http_host;
        proxy_set_header X-Forwarded-Proto $http_x_forwarded_proto;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        location = / {
          if ($request_method != GET) { return 418; }
          if ($http_accept !~* "text/html") { return 418; }
          if ($arg_enter = "1") { return 418; }
          root /srv/welcome;
          add_header Cache-Control "no-store" always;
          try_files /index.html =404;
        }
        error_page 418 = @opencloud;
        location @opencloud { proxy_pass http://127.0.0.1:9200; }
        location / { proxy_pass http://127.0.0.1:9200; }
      }
    }
  '';
  containers = {
    opencloud = {
      image = "docker.io/opencloudeu/opencloud-rolling@sha256:99698aea6bd88cf28004c773941cf69e2d24da136a3a45f9819b90b60506d14d";
      command = [ "server" ];
      environment = {
        OC_URL = public.url;
        PROXY_TLS = "false";
        PROXY_HTTP_ADDR = "127.0.0.1:9200";
        PROXY_CSP_CONFIG_FILE_LOCATION = "/etc/opencloud/csp.yaml";
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
        WEB_UI_CORE_APPS = lib.concatStringsSep "," ([ "files" "search" "text-editor" "external" "admin-settings" "preview" "app-store" "rclone-crypt" ] ++ lib.optional instance.apps.pdfViewer "pdf-viewer" ++ lib.optional instance.apps.epubReader "epub-reader");
        WEB_OPTION_DISABLE_SPONSOR_LINK = "true";
        WEBFINGER_WEB_OIDC_CLIENT_ID = "valhallishe-opencloud";
        WEBFINGER_DESKTOP_OIDC_CLIENT_ID = "valhallishe-opencloud";
        WEBFINGER_ANDROID_OIDC_CLIENT_ID = "valhallishe-opencloud";
        WEBFINGER_IOS_OIDC_CLIENT_ID = "valhallishe-opencloud";
        WEB_ASSET_THEMES_PATH = "/opt/branding";
        WEB_UI_THEME_PATH = "/themes/opencloud/valhallishe.json";
      };
      volumes = [
        "/run/nixarchserver-opencloud/opencloud.yaml:/etc/opencloud/opencloud.yaml:ro"
        "${dataDir}:/var/lib/opencloud"
        "${proxy}:/etc/opencloud/proxy.yaml:ro"
        "${csp}:/etc/opencloud/csp.yaml:ro"
        "${apps}:/var/lib/opencloud/web/assets/apps:ro"
        "${theme}:/opt/branding:ro"
      ]
      ++ lib.optional separateFiles "${filesDir}:/var/lib/opencloud/storage/users"
      ++ lib.optional instance.apps.unzip "${appsConfig}:/etc/opencloud/apps.yaml:ro";
    };
    gateway = {
      image = "docker.io/library/nginx@sha256:65645c7bb6a0661892a8b03b89d0743208a18dd2f3f17a54ef4b76fb8e2f2a10";
      entrypoint = "nginx";
      command = [ "-g" "daemon off;" ];
      volumes = [ "${nginx}:/etc/nginx/nginx.conf:ro" "${welcome}:/srv/welcome:ro" ];
    };
    radicale = {
      image = "docker.io/opencloudeu/radicale@sha256:26047f5279cad5e02be725b2f7131043f77cc2a71e855021f347ba718f11e5be";
      volumes = [ "${radicaleDir}:/var/lib/radicale" "${radicaleConfig}:/etc/radicale/config:ro" ];
    };
  };
  oci = import ../../../lib/rootless-podman.nix {
    inherit pkgs home runtime;
    name = "opencloud";
    uid = 956;
    subId = 396608;
    registryRepositories = map (container: builtins.head (lib.splitString "@" container.image)) (builtins.attrValues containers);
  };
  resolver = pkgs.writeText "opencloud-resolv.conf" "nameserver 1.1.1.1\n";
  runContainer = name:
    let
      container = containers.${name};
      volumes = map (value: "--volume " + lib.escapeShellArg value) container.volumes;
      environment = lib.mapAttrsToList (key: value: "--env " + lib.escapeShellArg "${key}=${value}") (container.environment or { });
      args = volumes ++ environment ++ lib.optional (container ? entrypoint) "--entrypoint ${container.entrypoint}";
    in ''
      podman run "''${common[@]}" --name opencloud-${name} ${lib.concatStringsSep " " args} \
        ${container.image} ${lib.escapeShellArgs (container.command or [ ])}
    '';
  oidc = pkgs.writeText "opencloud-authentik.py" ''
    url = ${builtins.toJSON public.url}
    ${builtins.readFile ./oidc.py}
  '';
  prepare = pkgs.writeShellScript "opencloud-prepare" ''
    set -euo pipefail
    export PATH=/usr/bin
    umask 077
    ${oci.setup}
    ${mounts.check}
    for directory in ${lib.escapeShellArgs directories}; do
      test -d "$directory"
    done
    ${decrypt ../../../secrets/nixarchserver-opencloud.age} > ${runtime}/opencloud.yaml
    chown ${oci.account}:${oci.account} ${runtime}/opencloud.yaml
    ${execAuthentik} < ${oidc}
  '';
  run = pkgs.writeShellScript "opencloud-podman-stack" ''
    set -euo pipefail
    podman() { ${oci.podman} "$@"; }
    if [[ "$1" = stop ]]; then
      if podman pod exists opencloud; then
        podman pod stop -t 30 opencloud
        podman pod rm opencloud
      fi
      exit 0
    fi

    "$0" stop
    podman pod create --name opencloud --share net --network none \
      --userns keep-id:uid=1000,gid=1000 --sysctl net.ipv4.ip_unprivileged_port_start=0
    common=(--detach --pod opencloud --pull=missing --restart=on-failure \
      --user 1000:1000 --cap-drop ALL --security-opt no-new-privileges --pids-limit 512 \
      --volume ${resolver}:/etc/resolv.conf:ro)
    ${lib.concatMapStrings runContainer [ "radicale" "opencloud" "gateway" ]}
  '';
  connect = pkgs.writeShellScript "opencloud-connect" ''
    set -euo pipefail
    export PATH=/usr/bin
    podman() { runuser -u ${oci.account} -- ${oci.podman} "$@"; }
    infra=$(podman pod inspect -f '{{.InfraContainerID}}' opencloud)
    pid=$(podman inspect -f '{{.State.Pid}}' "$infra")
    ${network}/bin/up "$pid"
    for attempt in {1..60}; do
      if nsenter -t "$pid" -n curl --fail --silent --max-time 2 -H 'Host: ${public.authority}' http://127.0.0.1/config.json >/dev/null; then
        exit 0
      fi
      sleep 1
    done
    exit 1
  '';
in {
  unit = pkgs.writeTextDir "nixarchserver-opencloud.service" ''
    [Unit]
    Description=OpenCloud and private Radicale in rootless Podman
    Requires=nixarchserver-awg-service-addresses.service nixarchserver-authentik.service
    After=nixarchserver-awg-service-addresses.service nixarchserver-authentik.service
    ${mounts.unitConfig}

    [Service]
    Type=oneshot
    RemainAfterExit=yes
    RuntimeDirectory=nixarchserver-opencloud
    RuntimeDirectoryMode=0711
    ExecStartPre=${prepare}
    ExecStart=/usr/bin/runuser -u ${oci.account} -- ${run} start
    ExecStartPost=${connect}
    ExecStopPost=${network}/bin/down
    ExecStopPost=/usr/bin/runuser -u ${oci.account} -- ${run} stop
    TimeoutStartSec=300
    Delegate=yes
  '';
}
