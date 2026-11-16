{
  lib,
  domain,
  routes,
  certificate,
  acmeAddress ? "127.0.0.1:8008",
}:
let
  indexed = lib.imap0 (i: r: r // { id = "route_${toString i}"; }) routes;
  groups = lib.groupBy (r: toString r.in_port) indexed;
  domains = lib.unique (
    [ domain ] ++ map (r: r.domain) (lib.filter (r: r.tls == "terminate" && r.domain != null) routes)
  );
  cert = certificate;
  tcp = r: r.protocol == "tcp";
  address = node: if lib.hasInfix ":" node.ip then "[${node.ip}]" else node.ip;
  send =
    r:
    {
      none = "";
      v1 = " send-proxy";
      v2 = " send-proxy-v2";
      v2-ssl = " send-proxy-v2-ssl";
    }
    .${r.proxy_protocol.send};
  backend = r: ''
    backend ${r.id}
      mode ${if tcp r then "tcp" else "http"}
      server target ${address r.out_node}:${toString r.out_port}${
        lib.optionalString (r.out_protocol == "https")
          " ssl verify required ca-file /etc/ssl/certs/ca-certificates.crt sni str(${r.domain}) verifyhost ${r.domain}"
      }${send r}
  '';
  frontend =
    port: rs:
    let
      r = builtins.head rs;
    in
    ''
      frontend port_${port}
        mode ${if tcp r then "tcp" else "http"}
        bind :${port}${
          lib.optionalString (r.tls == "terminate") " ssl crt ${cert}"
        }${lib.optionalString r.proxy_protocol.accept " accept-proxy"}
        ${
          if tcp r then
            "default_backend ${r.id}"
          else
            ''
              ${lib.optionalString (port == "80") "use_backend acme if { path_beg /.well-known/acme-challenge/ }"}
              http-request del-header Forwarded
              http-request del-header X-Forwarded-For
              http-request del-header X-Real-IP
              http-request set-header X-Real-IP %[src]
              http-request set-header X-Forwarded-Proto ${if r.tls == "terminate" then "https" else "http"}
              option forwardfor
              ${lib.optionalString (
                port == "443"
              ) "http-request return status 200 if { hdr(host),field(1,:) -i ${domain} }"}
              ${lib.concatMapStringsSep "\n" (
                r: "use_backend ${r.id} if { hdr(host),field(1,:) -i ${r.domain} }"
              ) rs}
              default_backend unmatched
            ''
        }
    '';
  reserved80 = ''
    frontend http_acme
      bind :80
      mode http
      http-request redirect scheme https code 301 unless { path_beg /.well-known/acme-challenge/ }
      use_backend acme if { path_beg /.well-known/acme-challenge/ }
  '';
  reserved443 = ''
    frontend landing
      bind :443 ssl crt ${cert}
      mode http
      http-request return status 200 if { hdr(host),field(1,:) -i ${domain} }
      default_backend unmatched
  '';
in
{
  assertions = [
    {
      assertion = lib.all (
        r:
        (r.protocol == "https" -> r.tls == "terminate")
        && (r.protocol == "http" -> r.tls == "none")
        && (r.tls == "passthrough" -> tcp r)
        && (!tcp r || r.out_protocol == "http")
        && ((r.tls == "terminate" || !tcp r) -> r.domain != null)
        && (r.proxy_protocol.send == "v2-ssl" -> r.tls == "terminate")
      ) routes;
      message = "Invalid proxy route: HTTP requires a domain, HTTPS terminates TLS, passthrough requires TCP, and v2-ssl requires TLS termination. TCP backends use raw transport (out_protocol=http).";
    }
    {
      assertion = lib.all (
        rs:
        let
          first = builtins.head rs;
        in
        if tcp first then
          builtins.length rs == 1
          && !(builtins.elem first.in_port [
            80
            443
          ])
        else
          lib.all (
            r:
            !tcp r
            && r.protocol == first.protocol
            && r.tls == first.tls
            && r.proxy_protocol.accept == first.proxy_protocol.accept
          ) rs
          && builtins.length (lib.unique (map (r: r.domain) rs)) == builtins.length rs
          && lib.all (r: r.domain != domain) rs
          && (first.in_port != 80 || (first.protocol == "http" && !first.proxy_protocol.accept))
          && (first.in_port != 443 || first.protocol == "https")
      ) (builtins.attrValues groups);
      message = "Conflicting proxy listeners: TCP requires a dedicated port; shared HTTP ports require compatible TLS/PROXY settings and unique domains. Ports 80/443 and the base domain are reserved for HTTP ACME/HTTPS.";
    }
  ];
  inherit domains;
  ports = lib.unique (
    [
      80
      443
    ]
    ++ map (r: r.in_port) routes
  );
  config = ''
    global
      log stdout format raw local0
    defaults
    ${import ./error-pages.nix { inherit lib; }}
      log global
      timeout connect 10s
      timeout client 1h
      timeout server 1h
      timeout tunnel 1h
    ${lib.optionalString (!(groups ? "80")) reserved80}
    ${lib.optionalString (!(groups ? "443")) reserved443}
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList frontend groups)}
    backend acme
      mode http
      server lego ${acmeAddress}
    backend unmatched
      mode http
      http-request deny deny_status 404
    ${lib.concatMapStringsSep "\n" backend indexed}
  '';
}
