# Inbuxa

Сервер и админка развёрнуты на Archserver через `/srv/docker/inbuxa/compose.yaml`.
Сервер и релей зафиксированы на 27.1-rc.5. Служба `infra-inbuxa.service`
запускает compose после Docker и туннеля, чтобы адрес 10.1.0.2 уже существовал. Данные и настройки сервера хранятся
в `/srv/docker/inbuxa/{data,config}`; их необходимо включить в резервное копирование.
Секреты веб-почты зашифрованы в `secrets/nixarchserver-inbuxa.age` и
расшифровываются SSH-ключом хоста в `/run/infra-inbuxa` при запуске юнита.
Учётные данные первоначальной настройки сохранены отдельно в зашифрованном
`secrets/inbuxa-bootstrap-archive.age` для администратора. Учётные записи
и данные сервера продолжают храниться в базе Inbuxa. Временный контейнер
`inbuxa-admin-setup` остановлен.

HAProxy на Halo завершает TLS для `mail.valhallishe.net` и
`admin.mail.valhallishe.net` и передаёт HTTP через AmneziaWG на Archserver.
Релей на Halo управляется NixOS, слушает SMTP на TCP 25 и принимает соединение
с сервера на 10.1.0.1:10443. Исходящая почта настроена через релей.
Его состояние и очередь в `/var/lib/inbuxa-relay` необходимо резервировать;
персональные ключи релея также хранятся в данных сервера.

Изменения NixOS должны попасть в ветку main репозитория Comin: иначе следующее
применение Comin может отменить маршруты и службу. Настройки Archserver
применяются отдельно. Соберите комплект командой
`nix build .#inbuxa-config --no-link --print-out-paths` и установите
`compose.yaml`, `nginx.conf` и `oauth.js` в `/srv/docker/inbuxa`.
Файл `infra-inbuxa.service` предназначен для `/etc/systemd/system/`.
После обновления Compose примените его в рабочем каталоге через
`docker compose up -d --no-build --pull never`. После изменения примонтированных
файлов пересоздайте контейнеры `proxy` и `webmail`. Публичные URL и OIDC issuer
берутся из маршрутов в `hosts/halo/_inventory.nix`. Для проверки `sudo systemctl status inbuxa-relay` и
`sudo -u inbuxa-relay /opt/inbuxa-relay/bin/inbuxa-relay status` на Halo.

DKIM-ключи сгенерированы сервером. При ручном DNS необходимо опубликовать оба
ключа из `dnsZoneFile` домена в админке и следить за ротацией ключей. Сертификат
SMTP релея сейчас самоподписанный. Клиентские SMTP/IMAP порты не опубликованы.

При отправке релей представляется как `mail.valhallishe.net`. Для проверки
SPF по SMTP HELO опубликуйте в зоне `valhallishe.net` отдельную TXT-запись
с именем `mail` и значением `v=spf1 ip4:31.76.34.221 -all`. Проверить запись
можно командой `dig +short TXT mail.valhallishe.net`.

Authentik выполняет вход в веб-почту через OIDC и создаёт ящики через SCIM.
Провайдер SCIM обращается к Inbuxa по адресу `http://10.1.0.2:18083/scim/v2`.
