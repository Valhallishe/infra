{ lib }:
let
  symbol = lib.replaceStrings [ ''fill="url(#ember)"'' ] [ ''fill="#ff8425"'' ] (builtins.readFile ../themes/authentik/assets/valhallishe-symbol.svg);
  pages = [
    { code = 400; reason = "Bad Request"; }
    { code = 403; reason = "Forbidden"; }
    { code = 404; reason = "Not Found"; }
    { code = 405; reason = "Method Not Allowed"; }
    { code = 408; reason = "Request Timeout"; }
    { code = 410; reason = "Gone"; }
    { code = 413; reason = "Content Too Large"; }
    { code = 425; reason = "Too Early"; }
    { code = 429; reason = "Too Many Requests"; }
    { code = 500; reason = "Internal Server Error"; }
    { code = 501; reason = "Not Implemented"; }
    { code = 502; reason = "Bad Gateway"; }
    { code = 503; reason = "Service Unavailable"; }
    { code = 504; reason = "Gateway Timeout"; }
  ];
  html = page: ''
    <!doctype html>
    <html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
    <meta name="color-scheme" content="dark"><title>${toString page.code} · Valhallishe</title>
    <style>
      :root{color-scheme:dark;font-family:system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;background:#0b0907;color:#ff8425}
      *{box-sizing:border-box}body{margin:0;min-height:100vh;min-height:100dvh;display:grid;place-items:center;padding:1.5rem}
      main{text-align:center}.brand{display:flex;align-items:center;justify-content:center;gap:.9rem;font-size:clamp(1.05rem,5vw,1.5rem);font-weight:750;letter-spacing:.14em}
      .brand svg{width:3.25rem;height:3.25rem;flex:none}.code{margin:2rem 0 0;font-size:clamp(3rem,12vw,4.5rem);line-height:1;font-weight:750;letter-spacing:.03em;color:#ff8425}
    </style></head><body><main><div class="brand">${symbol}<span>VALHALLISHE</span></div>
    <h1 class="code">${toString page.code}</h1>
    </main></body></html>
  '';
  response = page:
    let body = html page;
    in builtins.toFile "valhallishe-error-${toString page.code}.http" (
      "HTTP/1.1 ${toString page.code} ${page.reason}\r\nContent-Type: text/html; charset=utf-8\r\nCache-Control: no-store\r\nContent-Length: ${toString (builtins.stringLength body)}\r\n\r\n" + body
    );
in lib.concatMapStringsSep "\n" (page: "  errorfile ${toString page.code} ${response page}") pages
