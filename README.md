# Инфраструктура NixOS

Общие модули Denix/delib находятся в `modules/`, хосты и их схемы дисков Disko — в `hosts/`. Сейчас определён `nixosConfigurations.vps` для x86_64 VPS с UEFI, DHCP и одним диском. Это стартовый профиль: оборудование, сеть и загрузчик следует сверить с условиями конкретного провайдера. Dedicated-сервер можно добавить отдельным хостом с собственной схемой дисков и аппаратной конфигурацией.

Необязательный профиль `krozzzis` включает fish, vim и Starship. Настройки prompt скопированы из `osa-user` в `lib/starship.nix`; изменения исходного конфига нужно переносить сюда отдельно. Для значков нужен Nerd Font в терминале клиента.

## Структура конфигурации

- [`flake.nix`](flake.nix) передаёт деревья `hosts/` и `modules/` в Denix через `import-tree`. Для каждого NixOS-хоста `default.nix` содержит один `delib.host` и загружает локальные модули из `_nixos/`. Там лежат разметка Disko, параметры оборудования и сеть провайдера.
- [`infra.nix`](infra.nix) задаёт домен, подсеть и репозиторий Comin. Этот модуль загружает все `_inventory.nix` из дерева хостов. Один и тот же инвентарь доступен NixOS и сборкам для Arch.
- [`hosts/halo/_inventory.nix`](hosts/halo/_inventory.nix) задаёт адрес узла, соседа AWG, службы и публичные маршруты Halo.
- [`hosts/nixarchserver/_inventory.nix`](hosts/nixarchserver/_inventory.nix) задаёт узел Archserver, соседа AWG и параметры сервисов. [`_build.nix`](hosts/nixarchserver/_build.nix) собирает юниты systemd и скрипт активации для Arch.
- В [`modules/`](modules/) настройки профиля объявляются рядом с реализацией `delib.module`. Обычный обход `import-tree` пропускает пути с префиксом `_`. Например, схемы параметров сервисов из `modules/services/_options/` загружаются отдельно как подмодули инвентаря, а рецепты сборки вызываются явно.

При смене домена обновите внешние записи DNS и параметры приложений, которые хранятся
вне репозитория. Например, у PeerTube публичное имя является частью адресов ActivityPub.


## Halo

`nixosConfigurations.halo` описывает сервер `halo`: KVM, BIOS/GRUB, один диск `/dev/vda`, Btrfs с `compress=zstd` для корня, отдельный ext4 `/boot`, swap-файл 2 ГиБ и статическую сеть провайдера. Разметка находится в `hosts/halo/_nixos/disko.nix`. При установке этот диск полностью перезаписывается.

Маршруты Halo ссылаются на поток сервиса по имени хоста, сервиса и потока.
Шлюз завершает TLS для HTTP-потоков и проксирует их в туннель. Для TCP и UDP порт по умолчанию берётся из указанного потока.
NixOS ACME автоматически получает сертификаты; DNS-записи должны указывать на сервер,
а порты 80 и 443 должны быть доступны извне. DNS этим репозиторием не управляется.

[Туннель AmneziaWG](#общая-сеть-amneziawg) соединяет Halo и Archserver.
Публичные имена сервисов и `net.valhallishe.net` указывают на Halo. HAProxy принимает
HTTPS для `sso.valhallishe.net` и передаёт запросы к Authentik через туннель.

HAProxy также предоставляет `pass.valhallishe.net` по HTTPS, проксируя запросы к Vaultwarden на `archserver` через тот же туннель. DNS-запись этого имени управляется у DNS-провайдера.

Immich доступен через `photos.valhallishe.net`: Halo завершает HTTPS и
передаёт запросы через туннель на порт 2283 Archserver. DNS-запись управляется
у DNS-провайдера.

## Подготовка VPS

1. Убедитесь, что VPS загружается в UEFI, поддерживает DHCP и доступен по SSH из rescue-системы с правами root. При статической сети добавьте её конфигурацию в хост **до установки**. При BIOS загрузчик и разметку нужно изменить. Systemd-boot устанавливается в EFI-раздел, смонтированный в `/boot`, без изменения EFI NVRAM.
2. Через `lsblk -o NAME,SIZE,MODEL,TYPE` и `ls -l /dev/disk/by-id/` в rescue-системе определите целый диск. Укажите его стабильный путь в `hosts/vps/_nixos/disko.nix`. `CHANGE-ME` намеренно не является реальным диском. Disko полностью сотрёт выбранный диск, включая все разделы и данные.
3. Создайте свой профиль администратора в `modules/` и включите его через `myconfig` в `delib.host`. Образец `modules/krozzzis.nix` по умолчанию отключён; замените имя и публичный ключ перед включением. Без администратора с SSH-ключом после установки вход будет невозможен. Проверьте, что соответствующий приватный ключ доступен на машине управления. Парольный SSH и keyboard-interactive выключены, вход root по SSH запрещён. Пример профиля добавляет администратора в `wheel` и разрешает sudo без пароля.
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

Сервис объявляет именованные потоки в `infra.hosts.<host>.services`.
В [инвентаре Archserver](hosts/nixarchserver/_inventory.nix) запись
`services.authentik.flows.http.port = 5680;` задаёт внутренний порт.
В [инвентаре Halo](hosts/halo/_inventory.nix) маршрут в `gateway.routes`
ссылается на этот поток:

```nix
{
  domain = "sso.${config.infra.domain}";
  to = {
    host = "nixarchserver";
    service = "authentik";
    flow = "http";
  };
}
```

[Модули шлюза](modules/gateway/) вычисляют адрес назначения из overlay-адреса
хоста и порта потока. По умолчанию HTTP-поток публикуется через HTTPS на
443 с завершением TLS на Halo. Для HTTPS до backend задайте
`flows.<имя>.protocol = "https"`. TCP поддерживает `listen.tls = "none"`,
`"passthrough"` и `"terminate"`. UDP перенаправляется через nftables на
соседа AWG. Для TCP и UDP без завершения TLS домен используется как DNS-имя шлюза.

`listen.acceptProxyProtocol = true` требует PROXY-заголовок от входного соединения.
Включайте его только на входах от доверенного upstream proxy.
`flows.<имя>.proxyProtocol` поддерживает `none`, `v1`, `v2` и `v2-ssl`.
Последний вариант передаёт сведения о завершённом TLS. Backend должен явно
поддерживать выбранный PROXY protocol. По умолчанию он выключен в обе стороны.

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

[Halo](hosts/halo/_inventory.nix) и [Archserver](hosts/nixarchserver/_inventory.nix)
связывает интерфейс `infra0`. В инвентаре каждого хоста `node` указывает
на локальный узел, а `services.awg.peer` — на соседа.

| Узел | `hostId` | IP на `infra0` | Куда отправляет AWG-пакеты |
| --- | --- | --- | --- |
| Halo | 1 | `10.1.0.1/32` | На адрес и порт Archserver, полученные из его первого аутентифицированного пакета |
| Archserver (хост `nixarchserver`) | 2 | `10.1.0.2/32` | `net.valhallishe.net:51825/udp` с keepalive каждые 25 секунд при отсутствии трафика |

`net.valhallishe.net` должен указывать на публичный IP Halo. Archserver
инициирует соединение с Halo. После рукопожатия Halo может отправлять
трафик Archserver через тот же туннель. Префикс
`10.1.0.0/16` в [`infra.nix`](infra.nix) служит для расчёта IP по формуле «адрес сети + `hostId`». У каждого соседа свой маршрут `/32` и такой же `AllowedIPs`.
Обычный интернет-трафик идёт через маршрут провайдера.

```text
Браузер → sso.valhallishe.net:443 → HAProxy на Halo
        → HTTP через infra0 → Authentik на 10.1.0.2:5680
```

HAProxy завершает TLS и открывает отдельное соединение до backend.
Для Minecraft UDP 25565 Halo выполняет DNAT на `10.1.0.2:25565` и SNAT
на `10.1.0.1`, чтобы ответы Archserver шли обратно через туннель.

Модуль [AWG для NixOS](modules/awg.nix) читает пару `node` / `services.awg.peer`
из инвентаря Halo и поднимает `wireguard-infra0.service`. На Archserver
юнит `nixarchserver-awg.service` запускает `awg-quick` с конфигурацией из того
же инвентаря. В обоих случаях приватный ключ узла и публичный ключ соседа
берутся из файлов `.age` при запуске. Общие параметры интерфейса и
маскировки задаются в `infra.network`.

Для проверки на Halo выполните `sudo systemctl status wireguard-infra0.service`
и `ip route get 10.1.0.2`, на Archserver — `sudo systemctl status nixarchserver-awg.service`
и `ip route get 10.1.0.1`. Маршрут к соседу должен идти через `infra0`.
Команда `sudo awg show infra0` на обоих узлах показывает время последнего
рукопожатия и счётчики трафика.

Для добавления NixOS-узла задайте его `hostId`, локальный `node` и соседа
в `hosts/<host>/_inventory.nix`, добавьте ключи в `secrets/` и получателей
в `secrets/secrets.nix`. Приватный ключ должен расшифровываться на самом
узле, публичный — на его соседях. Добавьте новый узел в список соседей
противоположной стороны. Если у NixOS-узла несколько соседей, задайте их
списком в `nixos.infra.awg.peers` его `delib.host`.

## Minecraft

Halo публикует Java-сервер Valhallishe SMP по маршруту из `hosts/halo/_inventory.nix`:
`mc.play.${infra.domain}:25565` → Halo HAProxy → AWG → Archserver Velocity
на TCP 25565. Velocity направляет игроков в существующий `survival`.
HAProxy отправляет PROXY protocol v2 для сохранения адреса игрока;
на Velocity включён `advanced.haproxy-protocol`. TLS termination и ACME
для этого TCP-маршрута не используются. DNS-имя должно указывать на Halo;
дополнительная SRV-запись не требуется при стандартном порте 25565.
Второй маршрут этого же сервиса публикует Simple Voice Chat Proxy на UDP 25565
(в текущем конфиге Voice Chat `port=-1`, поэтому используется порт Velocity).
UDP обрабатывает общий `modules/gateway/udp.nix` через схему `lib/udp.nix`: nftables
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
