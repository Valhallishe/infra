{ pkgs, decrypt, instance, public, ssoUrl, network, configPackage, home }:
let
  inherit (pkgs) lib;
  inherit (instance) storage;
  runtime = "/run/infra-inbuxa";
  mounts = import ../../../lib/storage-mounts.nix { inherit lib; } [ storage.mail ];
  images = {
    server = "registry.coffeylabs.org/inbuxa/inbuxa-server@sha256:a04b74e60338e29211fc73adc171b556cd617dfe23a5d7e15687b9913a803560";
    webmail = "registry.coffeylabs.org/inbuxa/inbuxa-webmail@sha256:70d240165bb2da2060e1c6c2b17233f3984a4f148cab77e7a0207f2f70adfef4";
    admin = "registry.coffeylabs.org/inbuxa/inbuxa-admin@sha256:3c8b582e1f3b5d6cce34aa5563604e07a28982b02e3cf09d6c63bf8e5ef32e0e";
    nginx = "docker.io/library/nginx@sha256:65645c7bb6a0661892a8b03b89d0743208a18dd2f3f17a54ef4b76fb8e2f2a10";
  };
  oci = import ../../../lib/rootless-podman.nix {
    inherit pkgs home runtime;
    name = "inbuxa";
    uid = 954;
    subId = 527680;
    registryRepositories = map (image: builtins.head (lib.splitString "@" image)) (builtins.attrValues images);
  };
  resolver = pkgs.writeText "inbuxa-resolv.conf" "nameserver 1.1.1.1\n";
  nginx = pkgs.writeText "inbuxa-podman-nginx.conf" ''
    pid /tmp/nginx.pid;
    events {}
    http {
      include /etc/nginx/mime.types;
      client_body_temp_path /tmp/nginx-client;
      proxy_temp_path /tmp/nginx-proxy;
      fastcgi_temp_path /tmp/nginx-fastcgi;
      uwsgi_temp_path /tmp/nginx-uwsgi;
      scgi_temp_path /tmp/nginx-scgi;
      ${lib.replaceStrings
        [ "listen 8080;" "resolver 127.0.0.11 valid=10s;" "http://server:8080" "http://webmail:8080" ]
        [ "listen 80;" "" "http://127.0.0.1:8080" "http://127.0.0.1:8082" ]
        (builtins.readFile ./nginx.conf)}
    }
  '';
  admin = pkgs.writeText "inbuxa-podman-admin.conf" ''
    server {
      listen ${toString instance.flows.admin.port};
      root /usr/share/nginx/html;
      index index.html;
      location / {
        try_files $uri $uri/ /index.html;
      }
      location /assets/ {
        expires 1y;
        add_header Cache-Control "public, immutable";
      }
      location = /.well-known/source {
        default_type application/json;
        add_header Cache-Control "no-cache";
        add_header Access-Control-Allow-Origin "*";
        try_files $uri =404;
      }
      location = /index.html {
        add_header Cache-Control "no-cache";
      }
    }
  '';
  prepare = pkgs.writeShellScript "inbuxa-podman-preflight" ''
    set -euo pipefail
    umask 077
    ${mounts.check}
    test -s ${lib.escapeShellArg "${storage.config.location}/config.json"}
    test -d ${lib.escapeShellArg storage.mail.location}
    ${decrypt ../../../secrets/nixarchserver-inbuxa.age} > "$1/webmail-secrets.env"
    test -s "$1/webmail-secrets.env"
  '';
  prepareRuntime = pkgs.writeShellScript "inbuxa-podman-prepare" ''
    set -euo pipefail
    ${oci.setup}
    ${prepare} ${runtime}
    /usr/bin/chown ${oci.account}:${oci.account} ${runtime}/webmail-secrets.env
  '';
  command = pkgs.writeShellScript "inbuxa-podman-stack" ''
    set -euo pipefail
    podman() { ${oci.podman} "$@"; }
    # The OCI manifest can be unavailable during a registry outage. Accept the
    # exact image config ID from the previously running Docker deployment.
    selectImage() {
      if ! podman image exists "$1" && podman image exists "$2"; then
        printf '%s\n' "$2"
      else
        printf '%s\n' "$1"
      fi
    }
    if [[ $1 == stop ]]; then
      if podman pod exists inbuxa; then
        podman pod stop -t 40 inbuxa
        podman pod rm inbuxa
      fi
      exit 0
    fi

    podman pod create --name inbuxa --share net --network none \
      --userns keep-id:uid=2000,gid=2000 --sysctl net.ipv4.ip_unprivileged_port_start=0
    common=(--detach --pod inbuxa --pull=missing --restart=on-failure \
      --security-opt no-new-privileges --cap-drop ALL --pids-limit 512 \
      --volume ${resolver}:/etc/resolv.conf:ro)
    podman run "''${common[@]}" --name inbuxa-server --user 2000:2000 \
      --env ${lib.escapeShellArg "INBUXA_ADMIN_URL=${public.admin.url}"} \
      --env ${lib.escapeShellArg "INBUXA_PUBLIC_URL=${public.webmail.url}"} \
      --env ${lib.escapeShellArg "INBUXA_WEBMAIL_URL=${public.webmail.url}"} \
      --volume ${lib.escapeShellArg "${storage.config.location}:/etc/inbuxa"} \
      --volume ${lib.escapeShellArg "${storage.mail.location}:/var/lib/inbuxa"} \
      --entrypoint /bin/sh \
      "$(selectImage ${images.server} sha256:22a144062dddda6553a6297e7f78b966e5d3631cf37844ab7381b5c69a6ce071)" \
      -ec 'cp /usr/local/bin/inbuxa /tmp/inbuxa; exec /tmp/inbuxa --config /etc/inbuxa/config.json'
    podman run "''${common[@]}" --name inbuxa-webmail --user 1000:1000 \
      --env-file ${runtime}/webmail-secrets.env \
      --env PORT=8082 --env MAIL_SERVER_URL=http://127.0.0.1:8080 \
      --env ${lib.escapeShellArg "PUBLIC_URL=${public.webmail.url}"} \
      --env ${lib.escapeShellArg "ADMIN_URL=${public.admin.url}"} \
      --env ${lib.escapeShellArg "APP_NAME=${public.brand.name} Mail"} \
      --env ${lib.escapeShellArg "INBUXA_OIDC_ISSUER=${ssoUrl}/application/o/inbuxa-mail/"} \
      --volume ${./oauth.js}:/app/server/dist/oauth.js:ro \
      "$(selectImage ${images.webmail} sha256:81e71e71a637e34b2eeb0832fb74784fc00f51ff0b8a9d6083ac8a690dce7da7)"
    podman run "''${common[@]}" --name inbuxa-proxy --user 2000:2000 \
      --volume ${nginx}:/etc/nginx/nginx.conf:ro \
      --volume ${configPackage}/theme:/etc/nginx/theme:ro --entrypoint nginx \
      ${images.nginx} -g 'daemon off;'
    podman run "''${common[@]}" --name inbuxa-admin --user 101:101 \
      --env ${lib.escapeShellArg "API_BASE_URL=${public.webmail.url}"} \
      --volume ${admin}:/etc/nginx/conf.d/default.conf:ro \
      --entrypoint /bin/sh \
      "$(selectImage ${images.admin} sha256:9863e347a0432dfeffd8f2abf3e3657ab3c328a57e068b9ccc0a28ea0e64f20f)" \
      -ec '/docker-entrypoint.d/40-api-base-url.sh; exec nginx -g "daemon off;"'
  '';
  connect = pkgs.writeShellScript "inbuxa-connect" ''
    set -euo pipefail
    export PATH=/usr/bin
    podman() { runuser -u ${oci.account} -- ${oci.podman} "$@"; }
    infra=$(podman pod inspect -f '{{.InfraContainerID}}' inbuxa)
    pid=$(podman inspect -f '{{.State.Pid}}' "$infra")
    ${network}/bin/up "$pid"
    for attempt in {1..90}; do
      if nsenter -t "$pid" -n curl -fsS --max-time 3 http://127.0.0.1/ >/dev/null &&
         nsenter -t "$pid" -n curl -fsS --max-time 3 http://127.0.0.1:${toString instance.flows.admin.port}/ >/dev/null &&
         nsenter -t "$pid" -n curl -fsS --max-time 3 http://127.0.0.1:8080/.well-known/jmap >/dev/null; then
        exit 0
      fi
      sleep 1
    done
    exit 1
  '';
in
{
  inherit prepare;
  unit = pkgs.writeTextDir "infra-inbuxa.service" ''
    [Unit]
    Description=Inbuxa in rootless Podman
    Requires=nixarchserver-awg-service-addresses.service
    After=nixarchserver-awg-service-addresses.service
    ${mounts.unitConfig}

    [Service]
    Type=oneshot
    RemainAfterExit=yes
    RuntimeDirectory=infra-inbuxa
    RuntimeDirectoryMode=0711
    ExecStartPre=${prepareRuntime}
    ExecStart=/usr/bin/runuser -u ${oci.account} -- ${command} start
    ExecStartPost=${connect}
    ExecStopPost=${network}/bin/down
    ExecStopPost=/usr/bin/runuser -u ${oci.account} -- ${command} stop
    TimeoutStartSec=300
    Delegate=yes
  '';
}
