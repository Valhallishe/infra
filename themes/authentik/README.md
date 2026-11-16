# VALHALLISHE для authentik

Тема для authentik **2026.2.1** на `archserver`, опубликованного по адресу
https://sso.valhallishe.net. Прозрачный SVG повторяет контуры предоставленного
логотипа; оранжевый градиент — от `#ff8a22` до `#e34a17`. Фон страницы —
почти чёрный с мягким оранжевым свечением и геометрической сеткой.

- `assets/valhallishe-symbol.svg` — знак без фона, также favicon.
- `assets/valhallishe-logo.svg` — знак с надписью VALHALLISHE.
- `assets/background.svg` — фон страницы.
- `theme.css` — цвета, форма входа, кнопки и адаптация к мобильным экранам.
- `apply.py`, `restore.py`, `deploy.sh` — применение и откат через Django shell.

Логотип векторизован Potrace 1.16 после выделения оранжевых областей
из исходного изображения (красный канал, порог 35%, turdsize 12,
opttolerance 0.3). Растровое изображение в SVG не встроено.
Надпись использует системный DejaVu Sans с fallback на Arial/sans-serif.

## Применение

Из этого каталога:

```sh
./deploy.sh archserver
```

Нужны SSH и доступ к Docker. Скрипт использует штатные настройки бренда и
файловый менеджер authentik, не изменяет образ, compose или шаблоны.
Изменяется существующий бренд `default=True` (на момент установки —
`sso.sixty9.ru`), обслуживающий также `sso.valhallishe.net`.
Заголовок `default-authentication-flow` очищается, чтобы убрать приветствие
и оставить в заголовке вкладки только Valhallishe; его прежнее значение
также сохраняется для отката. Домен и провайдеры остаются прежними.
Тема по умолчанию становится тёмной; остальные атрибуты сохраняются.
Повторный запуск обновляет те же файлы и создаёт новую резервную копию.

Файлы сохраняются в постоянное хранилище `/data/media/public/valhallishe/`
(на хосте `/srv/docker/authentik/data/media/public/valhallishe/`). URL с
подписанными параметрами генерирует сам authentik; они не зашиты в теме.
Перезапуск контейнеров не требуется. Обновите страницу после применения.

## Откат

Перед каждым применением сохраняются прежние поля бренда в
`/data/valhallishe-backups/<timestamp>.json` с правами 0600. Эти копии
остаются на сервере, в Git не отправляются. Для отката после deploy:

```sh
ssh archserver 'docker exec -e VALHALLISHE_BACKUP=/data/valhallishe-backups/TIMESTAMP.json authentik-server-1 ak shell -c '\''exec(open("/tmp/valhallishe-theme/restore.py").read())'\'''
```

Замените `TIMESTAMP.json` именем нужной копии из вывода deploy.
После пересоздания контейнера сначала скопируйте `restore.py` в `/tmp`.
Резервные копии и загруженные SVG переживают пересоздание контейнера.

После обновления authentik проверьте CSS parts `main`/`branding`,
стили PatternFly и `.branding-logo`. Документация:
https://version-2026-2.goauthentik.io/brands/custom-css/.
