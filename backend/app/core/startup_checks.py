"""기동할 때 운영 설정을 점검한다.

`Settings` 의 검증기(`_guard_prod_secrets`)는 **값 하나만 보고 확실히 틀린 것**을
막는다. 여기는 그보다 넓다 — 여러 값을 엮어 보거나, 막기에는 이르지만 사람이 알아야
하는 상태를 경고로 남긴다. 앱 lifespan 이 DB 초기화 전에 부른다.

- 막는다(`StartupConfigError`): 잘못 적은 설정이라 고치지 않으면 기능이 틀리게 도는 것,
  그리고 운영에서 데이터를 잃는 설정(운영 + 로컬 첨부 저장소, #3029).
- 경고한다(WARN 로그): 개발에서는 정상이지만 운영이라면 사고인 것.
"""
from __future__ import annotations

import logging

from app.core.config import Settings
from app.services import attachment_store

logger = logging.getLogger("app.startup")


class StartupConfigError(RuntimeError):
    """설정이 서로 맞지 않아 기동하면 안 된다."""


#: (provider, 설정 이름, 값이 있는가) — 발급 앱을 확인하는 provider 의 허용 설정.
_SOCIAL_APP_SETTINGS = (
    ("google", "GOOGLE_CLIENT_IDS", lambda s: bool(s.google_client_id_list)),
    ("kakao", "KAKAO_APP_ID", lambda s: bool(s.kakao_app_id_value)),
    ("apple", "APPLE_CLIENT_IDS", lambda s: bool(s.apple_client_id_list)),
)


def unconfigured_social_providers(settings: Settings) -> list[str]:
    """허용 앱 설정이 비어 로그인을 거부하는 provider 목록(`google(GOOGLE_CLIENT_IDS)` 꼴).

    네이버는 설정과 무관하게 서버 측 코드 교환 전까지 닫혀 있어(501) 여기 넣지 않는다.
    """
    return [
        f"{provider}({name})"
        for provider, name, configured in _SOCIAL_APP_SETTINGS
        if not configured(settings)
    ]


def check(settings: Settings) -> list[str]:
    """설정을 점검하고 남긴 경고 문구를 돌려준다(테스트가 읽는다)."""
    warnings: list[str] = []

    # --- 채팅 첨부 저장소(#2817) ---
    try:
        backend = attachment_store.resolve_backend(settings)
    except RuntimeError as exc:
        raise StartupConfigError(str(exc)) from exc
    if backend == "local" and settings.is_prod:
        # 운영은 경고가 아니라 기동 거부다(#3029). 경고만 남기면 키를 빠뜨린 배포가
        # 배포 검증까지 통과하고, 다음 재배포 때 사진·리포트 PDF 가 사라진다.
        raise StartupConfigError(
            "운영(env=prod)에서는 채팅 첨부를 컨테이너 로컬 디스크에 저장할 수 없습니다 — "
            "재배포·스케일 아웃 때 사진·리포트 PDF 가 사라집니다. "
            "ATTACHMENT_STORAGE=s3 와 ATTACHMENT_S3_BUCKET 을 설정하세요."
        )
    if backend == "local" and settings.env.strip().lower() == "staging":
        # 시연 서버는 막지 않되, 첨부가 재배포 때 사라진다는 사실은 남긴다.
        warnings.append(
            "스테이징(env=staging)인데 채팅 첨부를 컨테이너 로컬 디스크에 저장합니다 — "
            "재배포 때 사진·리포트 PDF 가 사라집니다. 오래 쓸 시연이면 "
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

    # --- 소셜 로그인 발급 앱 확인(#3035) ---
    # 허용 앱 설정이 빈 provider 는 로그인을 거부한다(조용히 통과시키지 않는다). 막는
    # 쪽이 안전하지만, 운영에서 빠뜨리면 "소셜 로그인이 전부 401" 로만 보이므로 남긴다.
    missing = unconfigured_social_providers(settings)
    if missing:
        warnings.append(
            "소셜 로그인 허용 앱 설정이 비어 다음 로그인을 거부합니다: "
            + ", ".join(missing)
            + ". 각 provider 개발자 콘솔의 값을 넣으세요."
        )

    for message in warnings:
        logger.warning("[startup] %s", message)
    return warnings
