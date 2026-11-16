{ lib, domain }:
let
  symbol = builtins.readFile ../themes/authentik/assets/valhallishe-symbol.svg;
  pages = [
    { code = 400; reason = "Bad Request"; title = "Некорректный запрос"; message = "Сервер не смог обработать запрос. Проверьте адрес и попробуйте ещё раз."; }
    { code = 403; reason = "Forbidden"; title = "Доступ закрыт"; message = "У вас нет доступа к этой странице. Проверьте права или обратитесь к администратору."; }
    { code = 404; reason = "Not Found"; title = "Страница не найдена"; message = "Похоже, этого адреса здесь нет. Проверьте ссылку и попробуйте ещё раз."; }
    { code = 405; reason = "Method Not Allowed"; title = "Действие недоступно"; message = "Этот запрос нельзя выполнить для данного адреса."; }
    { code = 408; reason = "Request Timeout"; title = "Время ожидания истекло"; message = "Запрос выполнялся слишком долго. Попробуйте ещё раз."; }
    { code = 410; reason = "Gone"; title = "Страница больше недоступна"; message = "Запрошенный адрес больше не существует."; }
    { code = 413; reason = "Content Too Large"; title = "Слишком большой запрос"; message = "Попробуйте отправить данные меньшего размера."; }
    { code = 425; reason = "Too Early"; title = "Попробуйте ещё раз"; message = "Сервер пока не может безопасно обработать запрос."; }
    { code = 429; reason = "Too Many Requests"; title = "Слишком много запросов"; message = "Подождите немного и попробуйте снова."; }
    { code = 500; reason = "Internal Server Error"; title = "Что-то пошло не так"; message = "На сервере произошла ошибка. Попробуйте вернуться позже."; }
    { code = 501; reason = "Not Implemented"; title = "Действие не поддерживается"; message = "Сервер пока не умеет выполнять этот запрос."; }
    { code = 502; reason = "Bad Gateway"; title = "Сервис не отвечает"; message = "Не удалось получить ответ от сервиса. Попробуйте немного позже."; }
    { code = 503; reason = "Service Unavailable"; title = "Сервис временно недоступен"; message = "Возможно, он перезапускается или проходит обслуживание. Попробуйте немного позже."; }
    { code = 504; reason = "Gateway Timeout"; title = "Сервис не успел ответить"; message = "Время ожидания ответа истекло. Попробуйте ещё раз чуть позже."; }
  ];
  html = page: ''
    <!doctype html>
    <html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
    <meta name="color-scheme" content="dark"><title>${toString page.code} · Valhallishe</title>
    <style>
      :root{color-scheme:dark;font-family:system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;background:#0b0907;color:#fff0e4}
      *{box-sizing:border-box}body{margin:0;min-height:100vh;min-height:100dvh;display:grid;place-items:center;padding:2rem 1.25rem;background:radial-gradient(ellipse at 50% 35%,#55210d66,transparent 60%),#0b0907}
      body:before{content:"";position:fixed;inset:0;pointer-events:none;opacity:.22;background-image:linear-gradient(45deg,transparent 49.8%,#ff84251a 50%,transparent 50.2%),linear-gradient(-45deg,transparent 49.8%,#ff84251a 50%,transparent 50.2%);background-size:110px 110px}
      main{position:relative;width:min(100%,38rem);padding:clamp(2rem,6vw,4rem);border:1px solid #6d3a1c;border-top:3px solid #fa8025;border-radius:1.2rem;background:#17110ef2;box-shadow:0 24px 80px #0009;text-align:center}
      .brand{display:flex;align-items:center;justify-content:center;gap:.75rem;color:#ff8425;font-size:.8rem;font-weight:800;letter-spacing:.22em}.brand svg{width:2.5rem;height:2.5rem;flex:none}
      .code{margin:2.25rem 0 .5rem;font-size:clamp(5rem,18vw,8rem);line-height:1;font-weight:800;letter-spacing:-.07em;background:linear-gradient(145deg,#ffac55,#f1641c);color:#ff8425;background-clip:text;-webkit-text-fill-color:transparent}
      h1{margin:1rem 0 .75rem;font-size:clamp(1.4rem,5vw,1.9rem);line-height:1.2}p{max-width:29rem;margin:0 auto;color:#d2bdae;line-height:1.65}a{display:inline-block;margin-top:2rem;padding:.8rem 1.3rem;border:1px solid #ff8425;border-radius:.55rem;color:#ffad67;text-decoration:none;font-weight:650}a:hover{background:#ff8425;color:#1c0c03}a:focus-visible{outline:2px solid #ffbd84;outline-offset:4px}
    </style></head><body><main><div class="brand">${symbol}<span>VALHALLISHE</span></div>
    <div class="code" aria-hidden="true">${toString page.code}</div><h1>${page.title}</h1><p>${page.message}</p><a href="https://sso.${domain}/">К сервисам</a>
    </main></body></html>
  '';
  response = page:
    let body = html page;
    in builtins.toFile "valhallishe-error-${toString page.code}.http" (
      "HTTP/1.1 ${toString page.code} ${page.reason}\r\nContent-Type: text/html; charset=utf-8\r\nCache-Control: no-store\r\nContent-Length: ${toString (builtins.stringLength body)}\r\n\r\n" + body
    );
in lib.concatMapStringsSep "\n" (page: "  errorfile ${toString page.code} ${response page}") pages
