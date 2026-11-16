"""Run inside `ak shell`; update only branding fields on the existing default brand."""
import json
from datetime import datetime, timezone
from pathlib import Path

from django.db import transaction
from authentik.admin.files.manager import get_file_manager
from authentik.admin.files.usage import FileUsage
from authentik.brands.models import Brand
from authentik.flows.models import Flow

source = Path('/tmp/valhallishe-theme')
fields = ['branding_title', 'branding_logo', 'branding_favicon',
          'branding_custom_css', 'branding_default_flow_background', 'attributes']
with transaction.atomic():
    brand = Brand.objects.select_for_update().get(default=True)
    backups = Path('/data/valhallishe-backups')
    backups.mkdir(mode=0o700, parents=True, exist_ok=True)
    backup = backups / (datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ') + '.json')
    flow = Flow.objects.select_for_update().get(slug='default-authentication-flow')
    backup.write_text(json.dumps({'pk': str(brand.pk), 'flow_title': flow.title, **{f: getattr(brand, f) for f in fields}}, indent=2))
    backup.chmod(0o600)
    manager = get_file_manager(FileUsage.MEDIA)
    for asset in (source / 'assets').glob('*.svg'):
        manager.save_file('valhallishe/' + asset.name, asset.read_bytes())
    brand.branding_title = 'Valhallishe'
    brand.branding_logo = 'valhallishe/valhallishe-logo.svg'
    brand.branding_favicon = 'valhallishe/valhallishe-symbol.svg'
    brand.branding_default_flow_background = 'valhallishe/background.svg'
    brand.branding_custom_css = (source / 'theme.css').read_text()
    settings = brand.attributes.setdefault('settings', {})
    settings.setdefault('theme', {})['base'] = 'dark'
    brand.save(update_fields=fields)
    flow.title = ''
    flow.save(update_fields=['title'])
print(f'Applied VALHALLISHE to {brand.domain}; rollback: {backup}')
