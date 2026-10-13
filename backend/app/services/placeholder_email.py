"""소셜 가입 계정의 대체 이메일(#3338).

provider 가 확인된 이메일을 주지 않으면 계정 이메일 자리에
`{provider}_{provider_user_id}@social.oncare` 를 넣는다(`api/v1/social.py`). 받는 사람이
없는 내부용 주소라 회원에게 보여 주거나 메일을 보내면 안 된다. 만드는 규칙과 알아보는
규칙을 이 한 곳에 둔다 — 응답 스키마·안내 메일이 같은 판정을 쓴다.
"""
from __future__ import annotations

from app.services.contact_format import normalize_email

#: 대체 이메일의 도메인. 실제로 있는 도메인이 아니다.
PLACEHOLDER_EMAIL_DOMAIN = "social.oncare"

_SUFFIX = f"@{PLACEHOLDER_EMAIL_DOMAIN}"


def placeholder_email(provider: str, provider_user_id: str) -> str:
    """확인된 이메일이 없을 때 쓰는 대체 이메일. provider 신원마다 하나라 겹치지 않는다."""
    return normalize_email(f"{provider}_{provider_user_id}{_SUFFIX}")


def is_placeholder_email(email: str | None) -> bool:
    """[email] 이 대체 이메일인가. 대소문자·앞뒤 공백은 가리지 않는다."""
    return (email or "").strip().lower().endswith(_SUFFIX)


def placeholder_provider(email: str | None) -> str | None:
    """대체 이메일을 만든 provider(`kakao`·`google`). 대체 이메일이 아니면 None.

    앱이 주소 대신 가입 수단을 보여 줄 때 쓴다. 주소 앞부분이 규칙과 다르면
    (provider 자리가 비었으면) None 이다.
    """
    if not is_placeholder_email(email):
        return None
    local = (email or "").strip().lower()[: -len(_SUFFIX)]
    provider, sep, _ = local.partition("_")
    return provider if sep and provider else None
