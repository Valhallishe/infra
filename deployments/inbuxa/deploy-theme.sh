#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
host=${1:-archserver}
theme_dir=${SERVICE_THEMES:-$(nix build "path:$(cd ../.. && pwd)#service-themes" --no-link --print-out-paths)}
stage=$(mktemp -d)
trap 'rm -rf -- "$stage"' EXIT
cp "$theme_dir/inbuxa.css" "$stage/inbuxa.css"
cp -rL "$theme_dir/inbuxa-brand" "$stage/brand"
chmod u+w "$stage/brand"
cat > "$stage/webmail.conf" <<'NGINX'
proxy_set_header Host $host;
proxy_set_header X-Forwarded-Proto https;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header Accept-Encoding "";
sub_filter '</head>' '<link rel="stylesheet" href="/_infra/theme.css"></head>';
sub_filter_once off;
sub_filter_types application/javascript text/javascript application/manifest+json application/json;
sub_filter '2026-09-27a' 'BRAND_VERSION';
sub_filter '/assets/' '/_infra/build/BRAND_VERSION/assets/';
sub_filter '{id:`ihasmail`,name:`ihasmail`}' '{id:`ihasmail`,name:`ihasmail`},{id:`valhallishe`,name:`Valhallishe`}';
sub_filter 'ihasmail:{light:`linear-gradient' 'valhallishe:{light:`var(--valhallishe-preview-light)`,dark:`var(--valhallishe-preview-dark)`},ihasmail:{light:`linear-gradient';
sub_filter 'var D={theme:`ihasmail`,palette:`ihasmail`,mode:`dark`' 'var D={theme:`ihasmail`,palette:`valhallishe`,mode:`dark`';
NGINX
theme_version=$(cd "$stage" && sha256sum inbuxa.css webmail.conf brand/* | sha256sum | cut -c1-12)
sed -i "s|/_infra/theme.css|/_infra/theme.css?v=$theme_version|; s|BRAND_VERSION|$theme_version|" "$stage/webmail.conf"
sed -i "s|brand-light.svg|brand-light.svg?v=$theme_version|; s|brand-dark.svg|brand-dark.svg?v=$theme_version|" "$stage/inbuxa.css"
tar -C "$stage" -cf - inbuxa.css webmail.conf brand | ssh "$host" 'cd /srv/docker/inbuxa && docker compose exec -T proxy test -d /etc/nginx/theme </dev/null && mkdir -p theme && tar --no-same-permissions -xf - -C theme && docker compose exec -T proxy nginx -t && docker compose exec -T proxy nginx -s reload'
