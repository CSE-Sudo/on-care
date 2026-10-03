"""기동할 때 운영 설정을 점검한다.

`Settings` 의 검증기(`_guard_prod_secrets`)는 **값 하나만 보고 확실히 틀린 것**을
막는다. 여기는 그보다 넓다 — 여러 값을 엮어 보거나, 막기에는 이르지만 사람이 알아야
하는 상태를 경고로 남긴다. 앱 lifespan 이 DB 초기화 전에 부른다.

- 막는다(`StartupConfigError`): 잘못 적은 설정이라 고치지 않으면 기능이 틀리게 도는 것.
- 경고한다(WARN 로그): 개발에서는 정상이지만 운영이라면 사고인 것.
"""
from __future__ import annotations

import logging

from app.core.config import Settings
from app.services import attachment_store, password_reset

logger = logging.getLogger("app.startup")


class StartupConfigError(RuntimeError):
    """설정이 서로 맞지 않아 기동하면 안 된다."""


def check(settings: Settings) -> list[str]:
    """설정을 점검하고 남긴 경고 문구를 돌려준다(테스트가 읽는다)."""
    warnings: list[str] = []

    # --- 채팅 첨부 저장소(#2817) ---
    try:
        backend = attachment_store.resolve_backend(settings)
    except RuntimeError as exc:
        raise StartupConfigError(str(exc)) from exc
    if backend == "local" and settings.is_prod:
        warnings.append(
            "운영(env=prod)인데 채팅 첨부를 컨테이너 로컬 디스크에 저장합니다 — "
            "재배포·스케일 아웃 때 사진·리포트 PDF 가 사라집니다. "
            "ATTACHMENT_S3_BUCKET 을 설정하세요."
        )

    # --- 데모 폴백·데모 시드(#2821) ---
    # 개발에서는 정상이지만, 배포된 서버라면 로그인 없는 요청이 데모 회원으로 처리된다.
    # 배포 워크플로가 /healthz 로 다시 확인하지만, 로그에도 남겨 사람이 먼저 본다.
    if settings.demo_fallback_enabled:
        warnings.append(
            f"데모 폴백이 켜져 있습니다(env={settings.env}) — 토큰 없는 회원 API 요청이 "
            "데모 회원으로 처리됩니다. 배포 환경이면 ALLOW_DEMO_FALLBACK=false·ENV=prod 로 "
            "띄우세요."
        )
    # 운영 + 데모 시드는 경고가 아니라 설정 단계에서 기동을 거부한다(#2811) —
    # 이 검사까지 오지 않는다.

    # --- 비밀번호 재설정 메일 링크(#3033) ---
    # 링크 없이도 메일 속 코드로 재설정은 되므로 막지 않는다. 다만 경로형·http 주소는
    # 링크를 눌러도 앱이 코드를 받지 못해 "메일 링크가 안 된다" 로 드러난다.
    if settings.is_prod:
        for key, url in (
            ("PASSWORD_RESET_MEMBER_URL", settings.password_reset_member_url),
            ("PASSWORD_RESET_TRAINER_URL", settings.password_reset_trainer_url),
        ):
            problem = password_reset.reset_url_problem(url)
            if problem:
                warnings.append(
                    f"{key} 형식이 맞지 않습니다({problem}) — 메일 링크를 눌러도 재설정 "
                    "화면에 코드가 채워지지 않습니다. 해시형 주소를 넣으세요 "
                    "(예: https://<도메인>/frontend/#/auth/password-reset)."
                )

    for message in warnings:
        logger.warning("[startup] %s", message)
    return warnings
