#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
host=${1:-archserver}
# Only source assets and code are uploaded; no credentials are needed.
ssh "$host" 'mkdir -p /tmp/valhallishe-theme'
tar -cf - assets theme.css apply.py restore.py | ssh "$host" 'tar -xf - -C /tmp/valhallishe-theme'
ssh "$host" 'docker cp /tmp/valhallishe-theme authentik-server-1:/tmp/ && docker exec authentik-server-1 ak shell -c '\''exec(open("/tmp/valhallishe-theme/apply.py").read())'\'''
