#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
host=${1:-archserver}
theme_dir=${SERVICE_THEMES:-$(nix build "path:$(cd ../.. && pwd)#service-themes" --no-link --print-out-paths)}
stage=$(mktemp -d)
trap 'rm -rf -- "$stage"' EXIT
cp "$theme_dir/inbuxa.css" "$stage/inbuxa.css"
cat > "$stage/webmail.conf" <<'NGINX'
proxy_set_header Host $host;
proxy_set_header X-Forwarded-Proto https;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header Accept-Encoding "";
sub_filter '</head>' '<link rel="stylesheet" href="/_infra/theme.css"></head>';
NGINX
tar -C "$stage" -cf - inbuxa.css webmail.conf | ssh "$host" 'cd /srv/docker/inbuxa && docker compose exec -T proxy test -d /etc/nginx/theme && mkdir -p theme && tar -xf - -C theme && docker compose exec -T proxy nginx -t && docker compose exec -T proxy nginx -s reload'
