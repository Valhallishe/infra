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
Authentik вычисляются из маршрутов в `hosts/halo/_inventory.nix` и используются в Compose,
проверке API и настройке OIDC.

OpenCloud и Radicale описаны в `modules/services/opencloud`. Постоянные данные OpenCloud находятся в `/media/disk/opencloud`, коллекции
Radicale — отдельно в `/media/disk/radicale`; оба каталога необходимо
резервировать. Внутренняя
конфигурация и секреты OpenCloud зашифрованы в `secrets/nixarchserver-opencloud.age`
и расшифровываются при запуске в `/run`. Запуск проверяет UUID диска, а systemd останавливает
службу при его отключении. Radicale доступен только в сети контейнеров;
защищённые DAV-маршруты проходят через OpenCloud. Для отображения календаря
и контактов установлено стороннее расширение `opencloud-radicale-web-apps`.
Учетные записи создаются при первом входе через Authentik. Данные Nextcloud
автоматически не переносятся. Подключение Inbuxa не изменяется.

Приложения OpenCloud задаются в `services.opencloud.apps` инвентаря: EPUB,
PDF, 3D Viewer и Unzip включаются независимо. Версии внешних приложений и их
хеши закреплены в модуле. Панели Audio Info и Image Info встроены в файловое
приложение OpenCloud и появляются для файлов с соответствующими метаданными;
отдельных переключателей для них OpenCloud не предоставляет.

Vaultwarden на `https://pass.valhallishe.net` управляется юнитом
`nixarchserver-vaultwarden.service`. При первом переключении Compose
пересоздаёт контейнер в существующем проекте `vaultwarden` с той же версией
образа. База SQLite, вложения и настройки из панели администратора остаются
в `/srv/docker/vaultwarden/vw-data`. Перед переносом сохраните этот каталог
целиком при остановленном контейнере. Для возврата к прежней конфигурации
отключите новый юнит и запустите исходный Compose из `/srv/docker/vaultwarden`.

URL Vaultwarden и Authentik берутся из маршрутов Halo. Секрет клиента SSO,
токен администратора и ключи push хранятся в
`secrets/nixarchserver-vaultwarden.age`. Юнит расшифровывает их в
`/run/nixarchserver-vaultwarden`. Vaultwarden использует сохранённый
`config.json` для параметров, заданных через панель администратора.
