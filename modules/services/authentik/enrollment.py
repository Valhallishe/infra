"""Configure the invitation-only enrollment flow on the authentik instance."""

from django.db import transaction

from authentik.flows.models import Flow, FlowStageBinding
from authentik.policies.expression.models import ExpressionPolicy
from authentik.policies.models import PolicyBinding
from authentik.stages.invitation.models import InvitationStage
from authentik.stages.prompt.models import Prompt, PromptStage
from authentik.stages.user_login.models import UserLoginStage
from authentik.stages.user_write.models import UserWriteStage
from authentik.tenants.utils import get_current_tenant

SLUG = "valhallishe-invitation-enrollment"

VALIDATE_PROFILE = """
from base64 import b64decode
from binascii import Error
from django.core.exceptions import ValidationError
from django.core.validators import validate_email
from authentik.core.models import User

username = request.context["prompt_data"].get("username", "")
email = f"{username}@__MAIL_DOMAIN__"
try:
    validate_email(email)
except ValidationError:
    ak_message("Имя пользователя не подходит для почтового адреса.")
    return False
if User.objects.filter(email__iexact=email).exists():
    ak_message("Почтовый адрес для этого имени пользователя уже занят.")
    return False

avatar = request.context["prompt_data"].get("attributes.enrollment_avatar")
if not avatar:
    return True

header, _, encoded = avatar.partition(",")
signatures = {
    "data:image/png;base64": bytes.fromhex("89504e470d0a1a0a"),
    "data:image/jpeg;base64": bytes.fromhex("ffd8ff"),
}
signature = signatures.get(header)
if signature and len(encoded) <= 174764:
    try:
        image = b64decode(encoded, validate=True)
    except Error:
        pass
    else:
        if len(image) <= 128 * 1024 and image.startswith(signature):
            return True

ak_message("Загрузите PNG или JPEG размером до 128 КиБ.")
return False
""".strip().replace("__MAIL_DOMAIN__", MAIL_DOMAIN)

ENROLL_APPLICATION_GROUPS = """
from authentik.core.models import Group

plan = request.context["flow_plan"]
profile = plan.context["prompt_data"]
profile["name"] = profile.get("name", "").strip() or profile["username"]
profile["email"] = f"{profile['username']}@__MAIL_DOMAIN__"
profile.pop("password_repeat", None)

groups = Group.objects.filter(name__in=[
    "default-citizen",
    "inbuxa-mail-users",
    "vaultwarden-access",
    "immich-access",
    "opencloud-access",
    "peertube-access",
    "peertube-publishers",
    "vpn-portal-access",
])
plan.context["groups"] = [
    group for group in groups
    if not Group.objects.filter(pk=group.pk).with_ancestors()
    .filter(is_superuser=True).exists()
]
return True
""".strip().replace("__MAIL_DOMAIN__", MAIL_DOMAIN)


def apply():
    with transaction.atomic():
        flow, _ = Flow.objects.update_or_create(
            slug=SLUG,
            defaults={
                "name": "Valhallishe invitation enrollment",
                "title": "Создание аккаунта",
                "designation": "enrollment",
                "authentication": "require_unauthenticated",
            },
        )
        invitation, _ = InvitationStage.objects.update_or_create(
            name=f"{SLUG}-invitation",
            defaults={"continue_flow_without_invitation": False},
        )
        form, _ = PromptStage.objects.get_or_create(name=f"{SLUG}-profile")
        fields = [
            ("username", "Имя пользователя", "username", True),
            ("password", "Пароль", "password", True),
            ("password_repeat", "Повторите пароль", "password", True),
            ("name", "Отображаемое имя", "text", False),
            ("attributes.enrollment_avatar", "Аватар (PNG или JPEG, до 128 КиБ)", "file", False),
        ]
        prompts = []
        for order, (key, label, kind, required) in enumerate(fields):
            prompt, _ = Prompt.objects.update_or_create(
                name=f"{SLUG}-{key}",
                defaults={
                    "field_key": key,
                    "label": label,
                    "type": kind,
                    "required": required,
                    "order": order,
                },
            )
            prompts.append(prompt)
        form.fields.set(prompts)
        validation, _ = ExpressionPolicy.objects.update_or_create(
            name=f"{SLUG}-validate-profile",
            defaults={"expression": VALIDATE_PROFILE},
        )
        form.validation_policies.set([validation])
        write, _ = UserWriteStage.objects.update_or_create(
            name=f"{SLUG}-create-user",
            defaults={
                "user_creation_mode": "always_create",
                "user_type": "internal",
                "create_users_as_inactive": False,
                "create_users_group": None,
            },
        )
        login, _ = UserLoginStage.objects.get_or_create(name=f"{SLUG}-login")
        for order, stage in enumerate((invitation, form, write, login), start=1):
            binding, _ = FlowStageBinding.objects.update_or_create(
                target=flow,
                order=order * 10,
                defaults={
                    "stage": stage,
                    "evaluate_on_plan": False,
                    "re_evaluate_policies": True,
                },
            )
            if stage == write:
                group_policy, _ = ExpressionPolicy.objects.update_or_create(
                    name=f"{SLUG}-application-groups",
                    defaults={"expression": ENROLL_APPLICATION_GROUPS},
                )
                PolicyBinding.objects.update_or_create(
                    target=binding,
                    policy=group_policy,
                    defaults={"order": 0, "enabled": True},
                )

        tenant = get_current_tenant()
        avatar_mode = "attributes.enrollment_avatar"
        if avatar_mode not in tenant.avatars.split(","):
            tenant.avatars = f"{avatar_mode},{tenant.avatars}" if tenant.avatars else avatar_mode
            tenant.save(update_fields=["avatars"])


apply()
