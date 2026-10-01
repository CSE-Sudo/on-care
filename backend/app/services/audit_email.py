"""감사 로그에 남길 실패 이메일의 가명값. (#2911)

실패한 가입·로그인의 감사 기록(`audit_logs.detail`)에 입력 이메일을 원문으로 남기면,
탈퇴해도 지워지지 않고 남의 주소를 잘못 입력한 기록까지 보존 기간 없이 쌓인다.

그래서 원문 대신 **키를 둔 해시**(HMAC-SHA256, 서버 비밀 `JWT_SECRET`)의 앞 16자리를
적는다. 같은 대상에 대한 반복 시도(시도 제한·이상 탐지에 필요한 정보)는 같은 값으로
묶여 그대로 보이지만, 로그만으로는 주소를 되돌릴 수 없다. 키 없는 해시로 두면 흔한
주소 목록을 해시해 맞춰 보는 것만으로 원문이 드러나므로 키를 둔다.

대소문자·앞뒤 공백만 다른 입력은 같은 주소이므로 같은 값이 되도록 맞춘 뒤 해시한다.
비밀이 바뀌면 그 전 기록과는 묶이지 않는다 — 감사 대조는 같은 비밀 기간 안에서만 한다.
"""
from __future__ import annotations

import hashlib
import hmac

from app.core.config import get_settings

#: `detail` 에 붙는 접두. 원문이 아니라는 것을 읽는 사람이 바로 알게 한다.
PREFIX = "email_hash="


def masked_email(raw: str | None) -> str:
    """입력 이메일 → `email_hash=<16자리>`. 비어 있으면 빈 문자열."""
    normalized = (raw or "").strip().lower()
    if not normalized:
        return ""
    digest = hmac.new(
        get_settings().jwt_secret.encode("utf-8"),
        normalized.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()
    return f"{PREFIX}{digest[:16]}"
