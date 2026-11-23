# nixarchserver

Nix управляет Authentik, PeerTube и туннелем `infra0` на существующем Archserver.
Arch обслуживает Docker, firewall и системные пакеты. Имя узла в маршрутах
Halo остаётся `archserver` с адресом `10.1.0.2`. Comin использует имя
конфигурации `nixarchserver` и применяет ветку `main` этого репозитория.

Образы OCI, Compose и юниты systemd находятся в `modules/services/`. Authentik использует
Compose-проект `authentik`, внешний том `authentik_database` и существующие
каталоги в `/srv/docker/authentik`. Учётные записи, группы и настройки
провайдеров хранятся в PostgreSQL. Worker управляет Docker outpost, включая
действующий LDAP outpost. Порты 5680 и 56443 охраняет
`infra-docker-firewall.service`.

В `default.nix` задаются профиль брендинга, имя внешнего тома PostgreSQL и
каталог Authentik. После проверки готовности Authentik применяет выбранный
профиль к записи бренда по умолчанию. При изменении настроек предыдущие
значения сохраняются в `/data/valhallishe-backups`.

Пароль PostgreSQL и ключ Authentik находятся в
`secrets/nixarchserver-authentik.age`. AWG использует существующие
`archserver-awg.age` и `halo-awg-public.age`. Юниты расшифровывают файлы
SSH-ключом хоста в директории с правами 0700 под `/run`. При смене SSH-ключа
перешифруйте эти файлы. Редактируйте секреты через agenix из каталога
`secrets`. При смене пароля базы обновите пароль роли в PostgreSQL
согласованно с новым секретом.

На Archserver первичное развёртывание выполняется после установки Nix с
демоном, Docker Compose, AWG и firewall. Из доверенной копии репозитория:

```sh
release=$(nix --extra-experimental-features 'nix-command flakes' build \
  .#nixarchserver --no-link --print-out-paths)
sudo "$release/bin/preflight"
sudo "$release/bin/switch-to-configuration" switch
sudo systemctl start comin.service
```

Comin ожидает интерфейс `nixosConfigurations.*.config.system.build.toplevel`.
Для этого имени flake возвращает сборку с небольшим скриптом активации Arch.
Он обновляет юниты systemd и хранит активную сборку в профиле
`/nix/var/nix/profiles/nixarchserver`. При изменении конфига Comin сам
перезапускает свой юнит после записи результата применения.

Перед первым переключением проверьте восстановление зашифрованного
`pg_dump -Fc` в изолированном PostgreSQL 16. Остановите server и worker на
время финальной копии базы и архива `data`, `certs` и `custom-templates`.
Переключение переиспользует исходный том и версию PostgreSQL. Юнит AWG
проверяет совпадение конфигурации перед заменой старого активного юнита.
Выполняйте переключение через SSH по LAN, чтобы доступ пережил перезапуск
`infra0`. После переключения проверьте страницу входа через Halo,
состояние worker и LDAP outpost.

Резервные копии первого переноса находятся в `/var/backups/nixarchserver`.
Их можно расшифровать с помощью `age -d -i` ключом администратора или
хоста. Для проверки или восстановления используйте отдельную базу и
`pg_restore --single-transaction --exit-on-error`. Откат сборки меняет
конфигурацию, а для восстановления данных нужна отдельная операция.

PeerTube использует группы Authentik `PeerTube Access` для входа через SSO
и `PeerTube Publishers` для загрузки, импорта и создания трансляций. Для
публикации нужны обе группы. Членство меняется в Authentik и хранится в его
базе. PeerTube перечитывает права на публикацию примерно каждые 30 секунд,
в том числе для действующих сессий. Если снимок старше двух минут,
публикация через SSO блокируется. Публичные видео доступны без входа.

Квота видео по умолчанию составляет 50 ГиБ на пользователя. При применении
конфигурации прежняя безлимитная квота у учётных записей SSO заменяется
этим значением. Локальная учётная запись администратора сохраняет доступ
для обслуживания. Настройки OIDC применяются при запуске юнита, секрет
клиента берётся из `secrets/nixarchserver-peertube.age`. Публичные URL PeerTube и
Authentik вычисляются из маршрутов в `hosts/halo/_inventory.nix` и используются
в контейнерах, проверке API и настройке OIDC. PeerTube отвечает на
`10.1.2.3:80` через AWG. PostgreSQL и Redis работают внутри pod. Служебное
состояние хранится в `/var/lib/infra-services/peertube`, а видео и другие
файлы в `/media/disk/peertube-podman`. Исходные тома Docker и медиакаталог
сохранены.

OpenCloud, nginx и Radicale работают в одном rootless pod. Halo обращается к
`10.1.2.5:80` через AWG. Файлы пользователей остаются в
`/media/disk/opencloud/data/storage/users` и доступны контейнеру через ACL.
Служебное состояние OpenCloud и коллекции Radicale хранятся в
`/var/lib/infra-services/opencloud`. Исходные каталоги состояния сохранены.
Секреты OpenCloud зашифрованы в `secrets/nixarchserver-opencloud.age` и
расшифровываются в `/run`. Юнит проверяет UUID диска с файлами перед запуском.
DAV-маршруты проходят через OpenCloud, Radicale слушает loopback внутри pod.
Аккаунты создаются при первом входе через Authentik.

Приложения OpenCloud задаются в `services.opencloud.apps` инвентаря: EPUB,
PDF, 3D Viewer и Unzip включаются независимо. Версии внешних приложений и их
хеши закреплены в модуле. Панели Audio Info и Image Info встроены в файловое
приложение OpenCloud и появляются для файлов с соответствующими метаданными;
отдельных переключателей для них OpenCloud не предоставляет.

Vaultwarden на `https://pass.valhallishe.net` работает в rootless Podman
под управлением `nixarchserver-vaultwarden.service`. Halo обращается напрямую
к `10.1.2.6:80` через AWG. База SQLite, вложения и настройки хранятся в
`/var/lib/infra-services/vaultwarden/data`. Исходный каталог
`/srv/docker/vaultwarden/vw-data` сохранён в состоянии на момент переключения.
Перед возвратом к Docker нужно остановить запись и перенести актуальные данные.

URL Vaultwarden и Authentik берутся из маршрутов Halo. Секрет клиента SSO,
токен администратора и ключи push хранятся в
`secrets/nixarchserver-vaultwarden.age`. Юнит расшифровывает их в
`/run/nixarchserver-vaultwarden`. Vaultwarden использует сохранённый
`config.json` для параметров, заданных через панель администратора.

Immich на `https://photos.valhallishe.net` работает в отдельном rootless pod.
Halo обращается к `10.1.2.7:80` через AWG. PostgreSQL, Valkey и ML доступны
внутри pod. Медиатека остаётся в `/media/disk/immich`, а база, данные Valkey
и кеш моделей хранятся в `/var/lib/infra-services/immich`. Контейнерный
пользователь получает доступ к медиатеке через ACL. Исходные база и тома
Docker сохранены в состоянии на момент переключения.

Изоляция сети контейнеров на Archserver задаётся правилами
[`container-isolation.nft`](../../archserver/container-isolation.nft), которые
`nixarchserver-container-firewall.service` загружает до запуска Docker. Для
стандартных мостов `docker0` и `br-*` новые соединения к адресам хоста
отбрасываются до Docker DNAT; ответы на соединения, начатые хостом, разрешены.
Действующий `infra-docker-firewall.service` отдельно ограничивает входящие
опубликованные порты. При использовании Docker-моста с другим именем правила
нужно дополнить. Доступ Authentik worker к Docker socket остаётся исключением:
он необходим действующему управлению LDAP outpost и позволяет обойти изоляцию.

Caddy и Nextcloud AIO на Archserver отключены. Административный бот и его
исходящий прокси работают в отдельной сети Compose `/srv/docker/s9_admin_bot`;
порт сборщика опубликован только на адресе туннеля. Их конфигурация пока
управляется вне этого репозитория.
