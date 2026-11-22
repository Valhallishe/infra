#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
host=${1:-archserver}
theme_dir=${SERVICE_THEMES:-$(nix build "$(cd ../../.. && pwd)#service-themes" --no-link --print-out-paths)}
stage=$(mktemp -d)
trap 'rm -rf -- "$stage"' EXIT
cp "$theme_dir/inbuxa.css" "$stage/inbuxa.css"
cp -rL "$theme_dir/inbuxa-brand" "$stage/brand"
chmod u+w "$stage/brand"
cp "$theme_dir/inbuxa-webmail.conf" "$stage/webmail.conf"
theme_version=$(cd "$stage" && sha256sum inbuxa.css webmail.conf brand/* | sha256sum | cut -c1-12)
sed -i "s|/_infra/theme.css|/_infra/theme.css?v=$theme_version|; s|BRAND_VERSION|$theme_version|" "$stage/webmail.conf"
sed -i "s|brand-light.svg|brand-light.svg?v=$theme_version|; s|brand-dark.svg|brand-dark.svg?v=$theme_version|" "$stage/inbuxa.css"
tar -C "$stage" -cf - inbuxa.css webmail.conf brand | ssh "$host" 'cd /srv/docker/inbuxa && docker compose exec -T proxy test -d /etc/nginx/theme </dev/null && mkdir -p theme && tar --no-same-permissions -xf - -C theme && docker compose exec -T proxy nginx -t && docker compose exec -T proxy nginx -s reload'
