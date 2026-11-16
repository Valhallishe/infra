"""Run with VALHALLISHE_BACKUP=/data/valhallishe-backups/<timestamp>.json."""
import json
import os
from pathlib import Path
from django.db import transaction
from authentik.brands.models import Brand
from authentik.flows.models import Flow

path = Path(os.environ['VALHALLISHE_BACKUP']).resolve()
if path.parent != Path('/data/valhallishe-backups'):
    raise ValueError('Backup must be inside /data/valhallishe-backups')
data = json.loads(path.read_text())
pk = data.pop('pk')
flow_title = data.pop('flow_title', None)
allowed = {'branding_title', 'branding_logo', 'branding_favicon',
           'branding_custom_css', 'branding_default_flow_background', 'attributes'}
if set(data) != allowed:
    raise ValueError('Unexpected backup fields')
with transaction.atomic():
    brand = Brand.objects.select_for_update().get(pk=pk)
    for field, value in data.items():
        setattr(brand, field, value)
    brand.save(update_fields=list(data))
    if flow_title is not None:
        flow = Flow.objects.select_for_update().get(slug='default-authentication-flow')
        flow.title = flow_title
        flow.save(update_fields=['title'])
print('Brand restored')
