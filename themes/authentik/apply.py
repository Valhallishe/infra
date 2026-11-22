"""Run inside ak shell to apply the selected branding to the existing default brand."""
import json
from copy import deepcopy
from datetime import datetime, timezone
from hashlib import sha256
from pathlib import Path

from django.db import transaction
from authentik.admin.files.manager import get_file_manager
from authentik.admin.files.usage import FileUsage
from authentik.brands.models import Brand
from authentik.flows.models import Flow

source = Path(__file__).parent
profile = json.loads((source / "branding.json").read_text())
assets = {}
for filename in ("logo.svg", "symbol.svg", "background.svg"):
    data = (source / "assets" / filename).read_bytes()
    # Old backups retain working URLs when branding assets change.
    media_path = f"valhallishe/{sha256(data).hexdigest()}-{filename}"
    assets[filename] = (media_path, data)

with transaction.atomic():
    brand = Brand.objects.select_for_update().get(default=True)
    flow = Flow.objects.select_for_update().get(slug="default-authentication-flow")
    attributes = deepcopy(brand.attributes)
    attributes.setdefault("settings", {}).setdefault("theme", {})["base"] = "dark"
    desired = {
        "branding_title": profile["name"],
        "branding_logo": assets["logo.svg"][0],
        "branding_favicon": assets["symbol.svg"][0],
        "branding_default_flow_background": assets["background.svg"][0],
        "branding_custom_css": (source / "theme.css").read_text(),
        "attributes": attributes,
    }
    manager = get_file_manager(FileUsage.MEDIA)
    for path, data in assets.values():
        if not manager.file_exists(path):
            manager.save_file(path, data)

    previous = {field: getattr(brand, field) for field in desired}
    if previous != desired or flow.title:
        backups = Path("/data/valhallishe-backups")
        backups.mkdir(mode=0o700, parents=True, exist_ok=True)
        backup = backups / (datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ") + ".json")
        with backup.open("x") as file:
            backup.chmod(0o600)
            json.dump({"pk": str(brand.pk), "flow_title": flow.title, **previous}, file, indent=2)
        for field, value in desired.items():
            setattr(brand, field, value)
        brand.save(update_fields=list(desired))
        flow.title = ""
        flow.save(update_fields=["title"])
        print(f"Applied {profile['name']} to {brand.domain}; rollback: {backup}")
