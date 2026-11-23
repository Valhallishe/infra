# Inbuxa

Сервер, веб-почта, nginx и админка работают в rootless Podman под
управлением `infra-inbuxa.service` и Comin. Halo обращается к
`10.1.2.4:80` и `10.1.2.4:8081` через AWG. Почта хранится в
`/media/disk/inbuxa`, конфигурация находится в
`/var/lib/infra-services/inbuxa/config`. Исходные каталоги в
`/srv/docker/inbuxa` сохранены на момент переключения.
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

Nix формирует конфигурацию nginx, OAuth и тему. Публичные URL и адрес
OIDC issuer берутся из маршрутов в `hosts/halo/_inventory.nix`.

Для проверки релея на Halo используйте `systemctl status inbuxa-relay`.

DKIM-ключи сгенерированы сервером. При ручном DNS необходимо опубликовать оба
ключа из `dnsZoneFile` домена в админке и следить за ротацией ключей. Сертификат
SMTP релея сейчас самоподписанный. Клиентские SMTP/IMAP порты не опубликованы.

При отправке релей представляется как `mail.valhallishe.net`. Для проверки
SPF по SMTP HELO опубликуйте в зоне `valhallishe.net` отдельную TXT-запись
с именем `mail` и значением `v=spf1 ip4:31.76.34.221 -all`. Проверить запись
можно командой `dig +short TXT mail.valhallishe.net`.

Authentik выполняет вход в веб-почту через OIDC и создаёт ящики через SCIM.
Провайдер SCIM обращается к Inbuxa по адресу `https://mail.valhallishe.net/scim/v2`.
