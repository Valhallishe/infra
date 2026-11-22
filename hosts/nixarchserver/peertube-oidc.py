import json
import time

from django.db import transaction

from authentik.core.models import Application, Group, User
from authentik.crypto.models import CertificateKeyPair
from authentik.flows.models import Flow
from authentik.policies.models import PolicyBinding
from authentik.providers.oauth2.models import OAuth2Provider, RedirectURI, ScopeMapping, SubModes

with transaction.atomic():
    if configure:
        provider, _ = OAuth2Provider.objects.update_or_create(
            name="Valhallishe Videos",
            defaults=dict(
                client_id="peertube",
                client_secret=client_secret,
                sub_mode=SubModes.HASHED_USER_ID,
                authorization_flow=Flow.objects.get(slug="default-provider-authorization-implicit-consent"),
                invalidation_flow=Flow.objects.get(slug="default-provider-invalidation-flow"),
                signing_key=CertificateKeyPair.objects.get(name="authentik Self-signed Certificate"),
                redirect_uris=[RedirectURI("strict", "https://videos.valhallishe.net/plugins/auth-openid-connect/router/code-cb")],
            ),
        )
        provider.property_mappings.set(ScopeMapping.objects.filter(scope_name__in=["openid", "email", "profile"], managed__startswith="goauthentik.io/"))
        app, _ = Application.objects.update_or_create(
            slug="peertube",
            defaults=dict(name="Valhallishe Videos", provider=provider, policy_engine_mode="all"),
        )

        access, _ = Group.objects.get_or_create(name=settings["accessGroup"])
        publishers, _ = Group.objects.get_or_create(name=settings["publishGroup"])
        PolicyBinding.objects.update_or_create(
            target=app, group=access,
            defaults=dict(enabled=True, negate=False, order=0),
        )

    else:
        access = Group.objects.get(name=settings["accessGroup"])
        publishers = Group.objects.get(name=settings["publishGroup"])

    users = User.objects.filter(is_active=True).iterator()
    subjects = [user.uid for user in users if access.is_member(user) and publishers.is_member(user)]
    print("PEERTUBE_PUBLISH=" + json.dumps({
        "subjects": subjects,
        "expires": int((time.time() + settings["snapshotLifetime"]) * 1000),
    }))
