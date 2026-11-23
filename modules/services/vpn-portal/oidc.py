from django.db import transaction
from authentik.core.models import Application, Group
from authentik.crypto.models import CertificateKeyPair
from authentik.flows.models import Flow
from authentik.policies.expression.models import ExpressionPolicy
from authentik.policies.models import PolicyBinding
from authentik.providers.oauth2.models import OAuth2Provider, RedirectURI, ScopeMapping, SubModes

with transaction.atomic():
    provider, _ = OAuth2Provider.objects.update_or_create(
        client_id='vpn-portal',
        defaults={
            'name': 'Valhallishe Account',
            'client_type': 'confidential',
            'client_secret': client_secret,
            'sub_mode': SubModes.HASHED_USER_ID,
            'authorization_flow': Flow.objects.get(slug='default-provider-authorization-implicit-consent'),
            'invalidation_flow': Flow.objects.get(slug='default-provider-invalidation-flow'),
            'signing_key': CertificateKeyPair.objects.get(name='authentik Self-signed Certificate'),
            'redirect_uris': [RedirectURI('strict', 'https://account.valhallishe.net/api/auth/callback/oauth')],
        },
    )
    provider.property_mappings.set(ScopeMapping.objects.filter(scope_name__in=['openid', 'email', 'profile'], managed__startswith='goauthentik.io/'))
    app, _ = Application.objects.update_or_create(slug='vpn-portal', defaults={
        'name': 'Valhallishe Account', 'provider': provider, 'policy_engine_mode': 'any',
        'meta_launch_url': 'https://account.valhallishe.net/',
    })
    group, _ = Group.objects.get_or_create(name='vpn-portal-access')
    citizen = ExpressionPolicy.objects.get(name='default-citizen-access')
    for order, binding in ((10, {'group': group}), (20, {'policy': citizen})):
        PolicyBinding.objects.update_or_create(target=app, defaults={'order': order, 'enabled': True, 'negate': False}, **binding)
