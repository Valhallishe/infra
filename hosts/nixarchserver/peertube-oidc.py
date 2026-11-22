from django.db import transaction

from authentik.core.models import Application
from authentik.crypto.models import CertificateKeyPair
from authentik.flows.models import Flow
from authentik.providers.oauth2.models import OAuth2Provider, RedirectURI, ScopeMapping

with transaction.atomic():
    provider, _ = OAuth2Provider.objects.update_or_create(
        name="Valhallishe Videos",
        defaults=dict(
            client_id="peertube",
            client_secret=client_secret,
            authorization_flow=Flow.objects.get(slug="default-provider-authorization-implicit-consent"),
            invalidation_flow=Flow.objects.get(slug="default-provider-invalidation-flow"),
            signing_key=CertificateKeyPair.objects.get(name="authentik Self-signed Certificate"),
            redirect_uris=[RedirectURI("strict", "https://videos.valhallishe.net/plugins/auth-openid-connect/router/code-cb")],
        ),
    )
    provider.property_mappings.set(ScopeMapping.objects.filter(scope_name__in=["openid", "email", "profile"], managed__startswith="goauthentik.io/"))
    Application.objects.update_or_create(
        slug="peertube",
        defaults=dict(name="Valhallishe Videos", provider=provider),
    )
