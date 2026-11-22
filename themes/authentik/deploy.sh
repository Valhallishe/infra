#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
host=${1:-archserver}
theme_dir=${SERVICE_THEMES:-$(nix build "$(cd ../.. && pwd)#service-themes" --no-link --print-out-paths)}
ssh "$host" 'mkdir -p /tmp/valhallishe-theme'
tar -C "$theme_dir/authentik" -cf - . | ssh "$host" 'tar -xf - -C /tmp/valhallishe-theme'
ssh "$host" 'docker cp /tmp/valhallishe-theme authentik-server-1:/tmp/ && docker exec authentik-server-1 ak shell -c '\''import runpy; runpy.run_path("/tmp/valhallishe-theme/apply.py")'\'''
