# VALHALLISHE для authentik

Тема для authentik **2026.2.1** на `archserver`, опубликованного по адресу
https://sso.valhallishe.net. Прозрачный SVG повторяет контуры предоставленного
логотипа. Знак и надпись используют сплошной оранжевый цвет, фон страницы — тёмно-серый.

- `modules/branding/assets/valhallishe-symbol.svg` — знак без фона, также favicon.
- `modules/branding/assets/valhallishe-logo.svg` — знак с надписью VALHALLISHE.
- `modules/branding/assets/background.svg` — фон страницы.
- `theme.css` — шаблон Stylix для цветов, формы входа, кнопок и адаптации к мобильным экранам
  и переводы заголовка входа для языков authentik 2026.2.1. Заголовок
  задаётся через CSS и переключается вместе с языком страницы.
- `apply.py`, `restore.py`, `deploy.sh` — применение и откат через Django shell.

Логотип векторизован Potrace 1.16 после выделения оранжевых областей
из исходного изображения (красный канал, порог 35%, turdsize 12,
opttolerance 0.3). Растровое изображение в SVG не встроено.
Надпись использует системный DejaVu Sans с fallback на Arial/sans-serif.

## Применение

Юнит Authentik применяет профиль из `hosts/nixarchserver/_inventory.nix` после проверки
готовности приложения. Для ручного применения из этого каталога:

```sh
./deploy.sh archserver
```

Нужны Nix, SSH и доступ к Docker. Пакет собирается из профиля в `modules/branding/`. Готовый пакет можно
передать через `SERVICE_THEMES`. Тема применяется через штатные настройки
бренда и файловый менеджер Authentik.
Изменяется существующий бренд `default=True` (на момент установки —
`sso.valhallishe.net`).
Заголовок `default-authentication-flow` очищается, чтобы убрать приветствие
и оставить в заголовке вкладки только Valhallishe; его прежнее значение
также сохраняется для отката. Домен и провайдеры остаются прежними.
Тема по умолчанию становится тёмной; остальные атрибуты сохраняются.
Повторный запуск с тем же профилем не меняет запись и не создаёт копию.

Файлы сохраняются в постоянное хранилище `/data/media/public/valhallishe/`
(на хосте `/srv/docker/authentik/data/media/public/valhallishe/`). URL с
подписанными параметрами генерирует сам authentik; они не зашиты в теме.
Перезапуск контейнеров не требуется. Обновите страницу после применения.

## Откат

Перед изменением сохраняются прежние поля бренда в
`/data/valhallishe-backups/<timestamp>.json` с правами 0600. Эти копии
остаются на сервере, в Git не отправляются. Для отката после deploy:

```sh
ssh archserver 'docker exec -e VALHALLISHE_BACKUP=/data/valhallishe-backups/TIMESTAMP.json authentik-server-1 ak shell -c '\''exec(open("/tmp/valhallishe-theme/restore.py").read())'\'''
```

Замените `TIMESTAMP.json` именем нужной копии из вывода deploy.
При запуске через Nix файл отката доступен в `/opt/infra-branding/restore.py`. При следующем запуске юнит снова применит выбранный профиль.
Резервные копии и загруженные SVG переживают пересоздание контейнера.

После обновления authentik проверьте CSS parts `main`/`branding`,
стили PatternFly и `.branding-logo`. Документация:
https://version-2026-2.goauthentik.io/brands/custom-css/.
