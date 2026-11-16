"""Run with VALHALLISHE_BACKUP=/data/valhallishe-backups/<timestamp>.json."""
import json
import os
from pathlib import Path
from django.db import transaction
from authentik.brands.models import Brand

path = Path(os.environ['VALHALLISHE_BACKUP']).resolve()
if path.parent != Path('/data/valhallishe-backups'):
    raise ValueError('Backup must be inside /data/valhallishe-backups')
data = json.loads(path.read_text())
pk = data.pop('pk')
allowed = {'branding_title', 'branding_logo', 'branding_favicon',
           'branding_custom_css', 'branding_default_flow_background', 'attributes'}
if set(data) != allowed:
    raise ValueError('Unexpected backup fields')
with transaction.atomic():
    brand = Brand.objects.select_for_update().get(pk=pk)
    for field, value in data.items():
        setattr(brand, field, value)
    brand.save(update_fields=list(data))
print('Brand restored')
