# nixarchserver

Nix управляет Authentik и туннелем `infra0` на существующем Archserver.
Arch обслуживает Docker, firewall и системные пакеты. Имя узла в маршрутах
Halo остаётся `archserver` с адресом `10.1.0.2`. Comin использует имя
конфигурации `nixarchserver` и применяет ветку `main` этого репозитория.

В Nix описаны образы OCI, Compose и юниты systemd. Authentik использует
Compose-проект `authentik`, внешний том `authentik_database` и существующие
каталоги в `/srv/docker/authentik`. Учётные записи, группы и настройки
провайдеров хранятся в PostgreSQL. Worker управляет Docker outpost, включая
действующий LDAP outpost. Порты 5680 и 56443 охраняет
`infra-docker-firewall.service`.

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
Он обновляет три юнита systemd и хранит активную сборку в профиле
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
