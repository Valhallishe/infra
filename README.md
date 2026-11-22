# Инфраструктура NixOS

Общие модули Denix/delib находятся в `modules/`, хосты и их схемы дисков Disko — в `hosts/`. Сейчас определён `nixosConfigurations.vps` для x86_64 VPS с UEFI, DHCP и одним диском. Это стартовый профиль: оборудование, сеть и загрузчик следует сверить с условиями конкретного провайдера. Dedicated-сервер можно добавить отдельным хостом с собственной схемой дисков и аппаратной конфигурацией.

Необязательный профиль `krozzzis` включает fish, vim и Starship. Настройки prompt скопированы из `osa-user` в `lib/starship.nix`; изменения исходного конфига нужно переносить сюда отдельно. Для значков нужен Nerd Font в терминале клиента.

## Структура конфигурации

- [`infra.nix`](infra.nix) задаёт базовый домен, подсеть и репозиторий Comin.
- [`hosts/nixarchserver/default.nix`](hosts/nixarchserver/default.nix) перечисляет сервисы Arch, их порты, хранилища, профили брендинга и файлы секретов.
- [`hosts/halo/default.nix`](hosts/halo/default.nix) перечисляет службы Halo и именованные потоки, которые публикует шлюз. Например, `sso` ведёт на `nixarchserver.authentik.http`. Адрес и порт назначения вычисляются по конфигурации Arch.
- [`modules/services/`](modules/services/) содержит параметры, Compose, юниты и скрипты сервисов.
- [`modules/branding/`](modules/branding/) задаёт название, логотипы и палитры бренда. Привязка к Stylix тоже находится здесь.
- `nodes/` задаёт узлы туннеля. Адреса вычисляются из подсети и `hostId`.

При смене домена обновите внешние записи DNS и параметры приложений, которые хранятся
вне репозитория. Например, у PeerTube публичное имя является частью адресов ActivityPub.


## Halo

`nixosConfigurations.halo` описывает сервер `halo`: KVM, BIOS/GRUB, один диск `/dev/vda`, Btrfs с `compress=zstd` для корня, отдельный ext4 `/boot`, swap-файл 2 ГиБ и статическую сеть провайдера. Разметка находится в `hosts/halo/disko.nix`. При установке этот диск полностью перезаписывается.

Маршруты Halo ссылаются на поток сервиса по имени хоста, сервиса и потока.
Шлюз завершает TLS для HTTP-потоков и проксирует их в туннель. Для TCP и UDP порт по умолчанию берётся из указанного потока.
NixOS ACME автоматически получает сертификаты; DNS-записи должны указывать на сервер,
а порты 80 и 443 должны быть доступны извне. DNS этим репозиторием не управляется.

На `halo` и `archserver` отдельный туннель AmneziaWG связывает узлы без изменения маршрута интернет-трафика. NixOS-модуль Halo и юнит `nixarchserver-awg.service` используют общую топологию. Приватные ключи зашифрованы agenix отдельно для соответствующего хоста и администратора. Comin применяет изменения через [nixarchserver](hosts/nixarchserver/README.md).

Для системных сервисов зарезервирована сеть `10.1.0.0/16`. В туннеле `halo` использует `10.1.0.1`, а `archserver` — `10.1.0.2`. Маршруты создаются только к адресам настроенных узлов, а не ко всей зарезервированной сети.

`net.valhallishe.net` указывает на публичный адрес узла VPN. HAProxy на `halo` предоставляет `sso.valhallishe.net` по HTTPS и проксирует запросы к Authentik на `archserver` через туннель. DNS-записи обоих имён управляются у DNS-провайдера; при смене адреса сервера их необходимо обновить. Публично разрешены TCP 22, 80, 443, 25565 и UDP 51825, 25565 (AmneziaWG).

HAProxy также предоставляет `pass.valhallishe.net` по HTTPS, проксируя запросы к Vaultwarden на `archserver` через тот же туннель. DNS-запись этого имени управляется у DNS-провайдера.

Immich доступен через `photos.valhallishe.net`: Halo завершает HTTPS и
передаёт запросы через туннель на порт 2283 Archserver. DNS-запись управляется
у DNS-провайдера.

## Подготовка VPS

1. Убедитесь, что VPS загружается в UEFI, поддерживает DHCP и доступен по SSH из rescue-системы с правами root. При статической сети добавьте её конфигурацию в хост **до установки**. При BIOS загрузчик и разметку нужно изменить. Systemd-boot устанавливается в EFI-раздел, смонтированный в `/boot`, без изменения EFI NVRAM.
2. Через `lsblk -o NAME,SIZE,MODEL,TYPE` и `ls -l /dev/disk/by-id/` в rescue-системе определите целый диск. Укажите его стабильный путь в `hosts/vps/disko.nix`. `CHANGE-ME` намеренно не является реальным диском. Disko полностью сотрёт выбранный диск, включая все разделы и данные.
3. Создайте свой профиль администратора в `modules/`, подключите его во flake и включите для хоста. Образец `modules/krozzzis.nix` по умолчанию отключён; замените имя и публичный ключ перед включением. Без администратора с SSH-ключом после установки вход будет невозможен. Проверьте, что соответствующий приватный ключ доступен на машине управления. Парольный SSH и keyboard-interactive выключены, вход root по SSH запрещён. Пример профиля добавляет администратора в `wheel` и разрешает sudo без пароля.
4. Убедитесь, что есть доступ к консоли провайдера на случай ошибки сети или SSH. Если VPS не использует QEMU, отключите `services.qemuGuest.enable`.

## Установка

На машине управления с Nix и доступом по SSH к rescue-системе:

```sh
nix flake check . --no-build
nix run github:nix-community/nixos-anywhere -- --flake .#vps root@IP_СЕРВЕРА
```

При необходимости передайте параметры подключения согласно [документации nixos-anywhere](https://github.com/nix-community/nixos-anywhere/blob/main/docs/quickstart.md). Установка стирает диск; проверьте путь и резервные копии перед запуском. После перезагрузки проверьте SSH, сеть, firewall и сервисы:

```sh
ssh krozzzis@IP_СЕРВЕРА
systemctl status sshd fail2ban crowdsec crowdsec-firewall-bouncer
sudo fail2ban-client status sshd
sudo cscli metrics
sudo cscli bouncers list
sudo nft list ruleset
```

CrowdSec при первом запуске скачивает коллекцию SSH из Hub; для этого серверу нужен исходящий доступ в интернет. Он анализирует системный журнал и передаёт блокировки локальному firewall-bouncer. Fail2ban независимо использует свой SSH jail. Возможна блокировка собственного адреса: для восстановления используйте консоль провайдера. Внешние порты открываются явно при добавлении сервисов; SSH открыт модулем OpenSSH.

Для последующих изменений используется обычный NixOS flake, например `nixos-rebuild switch --flake .#vps --target-host krozzzis@IP_СЕРВЕРА --use-remote-sudo`. Хост `halo` также автоматически развёртывается через Comin.

Профиль включает zram (25% памяти), ограничение журналов, автоматический сбор мусора Nix старше 14 дней и хранение до пяти загрузочных поколений. Сбор мусора удаляет старые поколения и уменьшает доступный горизонт отката; резервные копии он не заменяет. Пример VPS использует ext4 без шифрования и swap-раздела; при необходимости настройте резервное копирование и шифрование под инфраструктуру провайдера. Обновление `flake.lock` и развёртывание обновлений выполняются отдельно.

Comin на `halo` проверяет ветку `main` на GitHub и применяет новые коммиты с закреплённым `flake.lock`. Автоматическая перезагрузка не выполняется. Для чтения по HTTPS репозиторий должен быть публичным. Любой, кто может изменить эту ветку, получает возможность выполнить код от root на сервере; защищайте ветку и доступ к репозиторию. Статус: `systemctl status comin` и `sudo comin status`.

Сетевая конфигурация `halo` зашифрована agenix в `secrets/halo-network.age` для SSH-ключей администратора и сервера. Для изменения используйте `agenix -e` в каталоге `secrets`. При переустановке необходимо сохранить SSH host key сервера и передать его в новую систему через `nixos-anywhere --extra-files`; новый host key потребует повторного шифрования секрета. Для своего сервера создайте собственную схему сети, ключи, секреты и настройки Comin.

## Создание секретов для новой установки

На машине управления создайте SSH-ключ администратора и получите публичные
host-ключи Halo и Archserver из доверенного источника. Подготовьте файл сети
systemd-networkd для Halo согласно настройкам провайдера. Затем выполните:

```sh
nix run .#bootstrap-secrets -- \
  --admin-key ~/.ssh/id_ed25519.pub \
  --halo-host-key /path/to/halo-ssh-host-key.pub \
  --arch-host-key /path/to/archserver-ssh-host-key.pub \
  --halo-network /path/to/10-wan.network \
  --output ./new-secrets
```

Команда создаёт зашифрованные файлы agenix и `secrets.nix` в новом каталоге;
она не перезаписывает существующий каталог. Создаются пары AWG, ключи и
пароли Authentik, PeerTube и Inbuxa. После проверки перенесите созданный
каталог на место `secrets/` в **новой** копии репозитория и добавьте файлы в
Git. Сохраните соответствующие приватные SSH-ключи в надёжной резервной копии.
Входной файл сети может содержать чувствительные данные; удалите его после
шифрования, если он больше не нужен.

Это генерация секретов, а не перенос существующих данных: она не меняет
пароли существующих PostgreSQL и OAuth-клиентов. Для нового Inbuxa нужно
зарегистрировать сгенерированную пару `OAUTH_CLIENT_ID` и
`OAUTH_CLIENT_SECRET` в сервере Inbuxa. Создание баз и их начальная настройка,
учётные записи, диски, DNS, конфигурация домена и подготовка хостов выполняются
отдельно. Не используйте новые секреты для действующей установки без
согласованной миграции данных и учётных данных сервисов.

## Структура деклараций и реализации

- `infra.nix` — базовый домен инфраструктуры, единственное место его настройки.
- `nodes/` — каталог узлов: hostId определяет адрес внутри общей подсети.
- `modules/services/` — именованные потоки `inbound` и `outbound` сервисов.
- `lib/declarations/` и `lib/nixos/` — декларации Denix и типы настроек.
- `modules/` — связующие модули; `modules/security/` — firewall, SSH,
  Fail2ban и CrowdSec.
- `lib/haproxy.nix` — построение конфигурации HAProxy и проверки маршрутов.
- `modules/haproxy.nix` — связь маршрутов gateway с NixOS HAProxy, ACME и firewall.
- `modules/awg.nix` — общий модуль подключения узла к AWG.
- `hosts/halo/` и `hosts/vps/` — состав хостов и параметры оборудования.

Деревья типов и узлов подключаются через `import-tree`. Ссылки на файлы
репозитория задаются от `inputs.self`.

Сервис объявляет потоки в `modules/services/`:

```nix
nixos.always.infra.services.example = {
  inbound.web = { };
  outbound.web = { node = "archserver"; port = 8080; };
};
```

Gateway включает `myconfig.infra.web.enable` и публикует конкретную пару потоков.
Пример записи в `nixos.infra.web.routes` из `hosts/halo/gateway.nix`:

```nix
{
  service = "example";
  inbound = "web";
  outbound = "web";
  domain = "example.${config.infra.domain}";
}
```

По умолчанию вход принимает HTTPS на 443 с завершением TLS, выход использует HTTP.
Для TLS до backend задайте `outbound.<имя>.protocol = "https"`.
TCP занимает отдельный порт и поддерживает `tls = "none"`, `"passthrough"`
и `"terminate"`. Для отправки PROXY protocol v2 задайте
`outbound.<имя>.proxyProtocol = "v2"`. UDP перенаправляется через nftables
на AWG peer. TCP и UDP без завершения TLS используют домен как DNS-имя gateway.

`inbound.<имя>.acceptProxyProtocol = true` требует PROXY-заголовок от входного соединения;
включайте его только на входах от доверенного upstream proxy.
`outbound.<имя>.proxyProtocol` поддерживает `none`, `v1`, `v2`, `v2-ssl`;
последний вариант передаёт сведения о завершённом TLS. Backend должен явно
поддерживать выбранный PROXY protocol: обычный sshd или HTTP-сервис такой
заголовок не принимает. По умолчанию PROXY protocol выключен в обе стороны.

Firewall открывает TCP-порты маршрутов и 80/443. HAProxy не публикует HTTP/3.
HTTP-маршруты одного порта должны иметь совместимые TLS/PROXY-настройки
и разные домены. Декларация не запускает backend и не открывает его порт
на выходном узле.

Сертификат с SAN для доменов всех TLS-терминируемых маршрутов выпускает
`security.acme` NixOS. HTTP-01 запросы HAProxy направляет на локальный
ACME listener `127.0.0.1:8008`. Базовый домен также включён в сертификат
и возвращает пустой ответ 200. Перед запуском HAProxy NixOS создаёт
предварительный сертификат; после успешного выпуска/продления HAProxy
выполняет graceful reload через USR2: существующие соединения остаются
у старого worker, новые принимает новый. Restart при обновлении сертификата
не вызывается. Все домены сертификата должны указывать на этот proxy,
порт 80 должен быть доступен извне. Email ACME по умолчанию —
`admin@${infra.domain}`; переопределяется через `security.acme.defaults.email`.

Ключи доступа хранятся в agenix; открытыми остаются получатели шифрования
в `secrets/secrets.nix`. Шаблон Arch требует подстановки `@HALO_PUBLIC_KEY@`
из `halo-awg-public.age` и приватного ключа из `archserver-awg.age`.


## Nextcloud и Immich

DNS для `files.valhallishe.net` и `photos.valhallishe.net` должен вести на Halo.
Halo получает сертификаты ACME для обоих имён и проксирует запросы на
Archserver: Nextcloud AIO на 6084, Immich на 2283.

Для переключения Nextcloud сделайте резервную копию AIO, замените
`cloud.sixty9.ru` на `files.valhallishe.net` в настройках mastercontainer
[по инструкции Nextcloud AIO](https://github.com/nextcloud/all-in-one#how-to-change-the-domain)
и перезапустите контейнеры через интерфейс AIO после публикации нового адреса.
Проверьте канонический URL и настройки интеграций Nextcloud.
Для Immich обновите публичный адрес сервера в настройках, если он задан,
и адрес в клиентах.

## Темы сервисов

Halo подключает Stylix с профилем из `modules/branding/`. Authentik применяет
профиль из своей декларации при запуске. Темы Inbuxa и Nextcloud можно
применить отдельно на Archserver:

```sh
export SERVICE_THEMES=$(nix build .#service-themes --no-link --print-out-paths)
./modules/services/inbuxa/deploy-theme.sh archserver
ssh archserver 'bash -s' < "$SERVICE_THEMES/nextcloud.sh"
```

Файлы Compose и nginx для Inbuxa собираются через `nix build .#inbuxa-config`.
Порядок обновления описан в [документации Inbuxa](modules/services/inbuxa/README.md).
Authentik получает CSS вместе с текущими логотипом и фоном, inbuxa загружает
CSS в webmail, Nextcloud получает основной цвет и цвет фона через OCC.

## Общая сеть AmneziaWG

`infra.nix` задаёт `infra.network.subnet` (сейчас `10.1.0.0/16`).
IP узла вычисляется как адрес сети плюс `hostId`: Halo — 1, Archserver — 2.
Backend-адреса сервисов автоматически используют вычисленный IP узла.
Поддерживается IPv4 CIDR с префиксом 0..30; адрес сети, broadcast и повторяющиеся
адреса узлов запрещены. По умолчанию интерфейс — `infra0`, порт — 51825;
общие параметры маскировки заданы в `infra.network.obfuscation`.

Для добавления NixOS-сервера:

1. Добавьте `nodes/newserver.nix` с `infra.nodes.newserver.hostId = 3`.
2. Зашифруйте ключи в `secrets/newserver-awg.age` и
   `secrets/newserver-awg-public.age`. Приватный ключ должен расшифровываться
   новым сервером, публичный — всеми его соседями. Добавьте получателей
   в `secrets/secrets.nix`; существующие публичные ключи соседей также нужно
   перешифровать для нового сервера.
3. В конфигурации хоста включите `nixos.infra.awg.enable = true`.
   Имя узла по умолчанию берётся из `networking.hostName`; его можно задать
   через `infra.awg.node`.

Соседи по умолчанию — все остальные узлы; список можно ограничить через
`infra.awg.peers = [ "halo" ]`. Для доступного извне узла задайте
`infra.nodes.<name>.awg.endpoint = "hostname:port"`.
Соседи с endpoint получают keepalive 25 секунд. Для узлов за NAT должен
существовать доступный сосед с endpoint; взаимная доступность всех пар
не возникает автоматически. Маршруты создаются только к IP соседей (/32).

Halo использует общий модуль; его `network.nix` содержит только настройки
провайдера и включение AWG. Ключи и команды настройки туннеля вынесены
в `modules/awg.nix`. Изменение зашифрованного ключа вызывает перезапуск
интерфейса при применении конфигурации.

Comin управляет Authentik, PeerTube и AWG на Archserver через конфигурацию
[nixarchserver](hosts/nixarchserver/README.md). Конфигурация туннеля Arch
генерируется из тех же `infra.network` и `infra.nodes`, что и на Halo.
Смена подсети меняет адреса сервисов и туннеля.

## Minecraft

Halo публикует Java-сервер Valhallishe SMP по маршруту из `hosts/halo/default.nix`:
`mc.play.${infra.domain}:25565` → Halo HAProxy → AWG → Archserver Velocity
на TCP 25565. Velocity направляет игроков в существующий `survival`.
HAProxy отправляет PROXY protocol v2 для сохранения адреса игрока;
на Velocity включён `advanced.haproxy-protocol`. TLS termination и ACME
для этого TCP-маршрута не используются. DNS-имя должно указывать на Halo;
дополнительная SRV-запись не требуется при стандартном порте 25565.
Второй маршрут этого же сервиса публикует Simple Voice Chat Proxy на UDP 25565
(в текущем конфиге Voice Chat `port=-1`, поэтому используется порт Velocity).
UDP обрабатывает общий `modules/udp.nix` через схему `lib/udp.nix`: nftables
выполняет DNAT на узел сервиса и SNAT на AWG-адрес входного узла.
Это обеспечивает обратный путь через туннель без маршрута по умолчанию на Halo.
PROXY protocol применяется только к TCP. Bedrock и UDP query не настраиваются.

Firewall входного узла вычисляется из маршрутов: HAProxy открывает TCP-порты,
UDP-модуль — UDP-порты и включает IPv4 forwarding с `filterForward = true`.
NixOS разрешает established/related и DNAT-соединения, прочий forwarding запрещён.
На Archserver Docker уже публикует TCP/UDP 25565 и создаёт разрешающие правила;
изменять контейнер и его firewall для этого маршрута не требуется.
Пустой `voice_host` в Voice Chat Proxy использует адрес подключения игрока;
при подключении по `mc.play.${infra.domain}` голосовой трафик идёт на Halo.
Проверять UDP нужно протоколом Simple Voice Chat, а не TCP-проверкой порта.

## Тема authentik

Кастомная тема VALHALLISHE для authentik на Archserver: прозрачный SVG логотипа,
надпись, favicon и тёмная палитра с оранжевыми акцентами. Исходники, применение
и откат описаны в [themes/authentik/README.md](themes/authentik/README.md).

## Страницы ошибок

HAProxy показывает страницы VALHALLISHE для собственных HTTP-ошибок, включая
неизвестный адрес (404) и недоступный backend (503). Шаблоны и сообщения
находятся в `lib/error-pages.nix`; логотип берётся из темы authentik. Ответы
с ошибками от самих сервисов и Cloudflare сохраняют оформление этих сервисов.
