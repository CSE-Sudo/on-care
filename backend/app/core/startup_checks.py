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
from app.core.db_url import pooler_problem
from app.services import attachment_store, password_reset

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


def places_search_problem(settings: Settings) -> str | None:
    """헬스장 찾기가 카카오 실검색을 못 해 빈 목록이 되는 설정이면 그 이유(#3161).

    키가 없거나 `PLACES_PROVIDER=seed` 면 장소 API 는 DB 장소만 읽는데, 데모 시드가
    꺼진 서버는 데모 장소를 빼므로 결과가 비게 된다(#2914).
    """
    if settings.places_provider == "seed":
        return "PLACES_PROVIDER=seed 라 카카오 장소 검색을 쓰지 않습니다"
    if not (settings.kakao_rest_api_key or "").strip():
        return "KAKAO_REST_API_KEY 가 비어 카카오 장소 검색을 쓰지 않습니다"
    return None


def check(settings: Settings) -> list[str]:
    """설정을 점검하고 남긴 경고 문구를 돌려준다(테스트가 읽는다).

    `errors` 는 기동은 막지 않지만 운영에서 기능이 사실상 멈춘 상태라 ERROR 로 남긴다.
    돌려주는 목록에는 둘 다 들어간다.
    """
    warnings: list[str] = []
    errors: list[str] = []

    # --- DB 엔드포인트(#3146) ---
    # 운영은 설정 단계에서 거부한다. 개발·스테이징은 막지 않되 남긴다.
    db_problem = pooler_problem(settings.database_url)
    if db_problem and not settings.is_prod:
        warnings.append(db_problem)

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

    # --- 예전 관리자 이메일 목록(#3037) ---
    # 기동 때 이 주소의 계정을 관리자로 올리던 동작은 없앴다. 값이 남아 있으면 운영자는
    # 아직 그렇게 된다고 믿을 수 있으므로 알린다 — 아무 계정도 바꾸지 않는다.
    if settings.admin_emails.strip():
        warnings.append(
            "ADMIN_EMAILS 가 설정돼 있지만 더 이상 쓰지 않습니다 — 기동 때 관리자를 "
            "지정하지 않습니다. 관리자는 scripts/grant_admin.py 로 지정하고 이 값을 지우세요."
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

    # --- 카카오 장소 검색 키(#3161) ---
    # 장소 검색은 핵심 경로가 아니라 기동은 막지 않는다(로그인·기록은 계속 돈다). 다만
    # 운영에서 빠뜨리면 헬스장 찾기가 늘 빈 목록이라, 회원은 "주변에 헬스장이 없다" 고
    # 받아들이고 운영자는 문의가 올 때까지 모른다. 그래서 운영은 ERROR 로 남긴다.
    # 개발은 키 없이 시드 장소로 도는 것이 정상이라 남기지 않는다.
    places_problem = places_search_problem(settings)
    if places_problem:
        if settings.is_prod:
            errors.append(
                f"{places_problem} — 운영(env=prod)에서는 헬스장 찾기가 항상 빈 목록입니다"
                "(데모 장소는 빼고 읽음, #2914). 운영 비밀의 KAKAO_REST_API_KEY 에 카카오 "
                "REST API 키를 넣고 PLACES_PROVIDER 는 auto 또는 kakao 로 두세요."
            )
        elif settings.env.strip().lower() == "staging":
            warnings.append(
                f"{places_problem} — 스테이징(env=staging)의 헬스장 찾기는 DB 장소만 "
                "보여 줍니다(데모 시드가 꺼져 있으면 빈 목록). 실검색을 확인하려면 "
                "KAKAO_REST_API_KEY 를 넣으세요."
            )

    for message in warnings:
        logger.warning("[startup] %s", message)
    for message in errors:
        logger.error("[startup] %s", message)
    return warnings + errors
