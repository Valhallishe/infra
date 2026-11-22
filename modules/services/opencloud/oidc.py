from django.db import transaction
from authentik.core.models import Application
from authentik.crypto.models import CertificateKeyPair
from authentik.flows.models import Flow
from authentik.providers.oauth2.models import OAuth2Provider, RedirectURI, ScopeMapping, SubModes

with transaction.atomic():
    provider, _ = OAuth2Provider.objects.update_or_create(
        client_id="valhallishe-opencloud",
        defaults={
            "name": "Valhallishe OpenCloud",
            "client_type": "public",
            "sub_mode": SubModes.HASHED_USER_ID,
            "authorization_flow": Flow.objects.get(slug="default-provider-authorization-implicit-consent"),
            "invalidation_flow": Flow.objects.get(slug="default-provider-invalidation-flow"),
            "signing_key": CertificateKeyPair.objects.get(name="authentik Self-signed Certificate"),
            "redirect_uris": [RedirectURI("strict", url + p) for p in ("/", "/oidc-callback.html", "/oidc-silent-redirect.html")]
                + [RedirectURI("regex", r"http://(127\.0\.0\.1|localhost)(:[0-9]+)?(/.*)?"),
                   RedirectURI("strict", "oc://android.opencloud.eu"),
                   RedirectURI("strict", "oc://ios.opencloud.eu")],
        },
    )
    provider.property_mappings.set(ScopeMapping.objects.filter(scope_name__in=["openid", "email", "profile", "offline_access"], managed__startswith="goauthentik.io/"))
    Application.objects.update_or_create(slug="opencloud", defaults={"name": "Valhallishe Files", "provider": provider})
