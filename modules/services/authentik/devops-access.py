"""Require an application-specific group for each Authentik application."""

from django.db import transaction

from authentik.core.models import Application, Group
from authentik.policies.expression.models import ExpressionPolicy
from authentik.policies.models import PolicyBinding
from authentik.rbac.models import Role

APPLICATION_GROUPS = {
    "grafana": "grafana-access",
    "remnawave": "remnawave-access",
    "vaultwarden": "vaultwarden-access",
    "inbuxa-mail": "inbuxa-mail-users",
    "immich": "immich-access",
    "peertube": "peertube-access",
    "opencloud": "opencloud-access",
}

with transaction.atomic():
    for old, new in {
        "Grafana Access": "grafana-access",
        "Remnawave Access": "remnawave-access",
        "Vaultwarden Access": "vaultwarden-access",
        "Immich Access": "immich-access",
        "OpenCloud Access": "opencloud-access",
        "PeerTube Access": "peertube-access",
        "PeerTube Publishers": "peertube-publishers",
    }.items():
        previous = Group.objects.filter(name=old).first()
        if previous:
            if Group.objects.filter(name=new).exists():
                raise ValueError(f"Both {old} and {new} exist; refusing to discard memberships")
            previous.name = new
            previous.save(update_fields=["name"])

    role, _ = Role.objects.get_or_create(name="default-citizen")
    citizen_group, _ = Group.objects.get_or_create(name="default-citizen")
    citizen_group.roles.add(role)
    citizen_policy, _ = ExpressionPolicy.objects.update_or_create(
        name="default-citizen-access",
        defaults={"expression": 'return request.user.is_authenticated and request.user.all_roles().filter(name="default-citizen").exists()'},
    )
    for slug, group_name in APPLICATION_GROUPS.items():
        application = Application.objects.get(slug=slug)
        group, _ = Group.objects.get_or_create(name=group_name)
        mode = "all" if slug in ("grafana", "remnawave") else "any"
        if application.policy_engine_mode != mode:
            application.policy_engine_mode = mode
            application.save(update_fields=["policy_engine_mode"])

        # Replace the previous specific-user and DevOps-role restrictions.
        if slug == "inbuxa-mail":
            PolicyBinding.objects.filter(target=application, user__username="krozzzis").delete()
        if slug in ("grafana", "remnawave"):
            PolicyBinding.objects.filter(
                target=application, policy__name="valhallishe-require-devops-role"
            ).delete()

        PolicyBinding.objects.update_or_create(
            target=application,
            group=group,
            defaults={"order": 10, "enabled": True, "negate": False, "failure_result": False},
        )
        if mode == "any":
            PolicyBinding.objects.update_or_create(
                target=application,
                policy=citizen_policy,
                defaults={"order": 20, "enabled": True, "negate": False, "failure_result": False},
            )
