#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
host=${1:-archserver}
theme_dir=${SERVICE_THEMES:-$(nix build "path:$(cd ../.. && pwd)#service-themes" --no-link --print-out-paths)}
stage=$(mktemp -d)
trap 'rm -rf -- "$stage"' EXIT
cp "$theme_dir/authentik.css" "$stage/theme.css"
# Only theme assets and code are uploaded.
ssh "$host" 'mkdir -p /tmp/valhallishe-theme'
tar -cf - assets apply.py restore.py -C "$stage" theme.css | ssh "$host" 'tar -xf - -C /tmp/valhallishe-theme'
ssh "$host" 'docker cp /tmp/valhallishe-theme authentik-server-1:/tmp/ && docker exec authentik-server-1 ak shell -c '\''exec(open("/tmp/valhallishe-theme/apply.py").read())'\'''
