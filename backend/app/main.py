"""
FastAPI 진입점.

프론트 계약에 맞춰 /v1 prefix 로 라우터를 마운트합니다.
실행: uvicorn app.main:app --reload
문서: http://localhost:8000/docs (운영은 기본으로 닫힌다 — EXPOSE_API_DOCS, #2834)
"""

from __future__ import annotations

import re
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware

from app.api import ai_call_errors
from app.api.v1 import (
    activity,
    admin_trainers,
    ai_coach,
    challenges,
    chat_attachments,
    coach_docs,
    consultations,
    dashboard,
    emotes,
    diet,
    exercise,
    gyms,
    member_coach,
    notifications,
    places,
    points,
    reservations,
    social,
    streak_shields,
    system,
    trainer,
    trainers,
    users,
)
from app.api.v1.trainer import notifications as trainer_notifications
from app.core import error_tracking, https_redirect, observability, startup_checks
from app.core.body_limit import BodyLimitRule, RequestBodySizeLimitMiddleware
from app.core.client_ip import warn_if_untrusted_setup
from app.core.client_platform import RequestClientPlatformMiddleware
from app.core.config import Settings, get_settings
from app.core.locale import RequestLocaleMiddleware
from app.core.security_headers import security_headers_for
from app.db.init_db import init_db
from app.services import mailer, retention

settings = get_settings()
# 로깅을 먼저 설정(요청 ID 포함 포맷). 이후 모듈 로거들이 이 설정을 따른다.
observability.setup_logging(settings.log_level)
# 에러 추적(#2839). SDK 가 FastAPI·Starlette 를 감싸므로 앱을 만들기 전에 초기화한다.
# SENTRY_DSN 이 없거나 ENV=dev 면 아무것도 하지 않는다.
error_tracking.init_error_tracking(settings)


@asynccontextmanager
async def lifespan(app: FastAPI):
    # 설정끼리 어긋나면 DB 를 건드리기 전에 멈추고, 운영에서 위험한 상태는
    # 경고로 남긴다(#2817·#2821).
    startup_checks.check(settings)
    # 프록시 뒤 운영에서 클라이언트 IP 를 소켓 주소로 읽게 설정됐으면 남긴다(#2815).
    warn_if_untrusted_setup(settings)
    init_db()
    # 보존 기한이 지난 감사 기록·읽은 알림 정리(#2830·#3144). 기동 때 한 번 돌고, 그 뒤로는
    # 하루마다 백그라운드에서 돈다 — 재시작 없이 오래 도는 태스크에서도 고지한 보관 기간을
    # 넘기지 않는다. 실패해도 기동·서비스는 계속된다.
    retention.run_purge()
    purge_task = retention.start_periodic()
    # 메일 발송 수단이 없으면 기동 로그에 드러낸다 — 운영이면 재설정이 꺼진다(#2824).
    mailer.warn_if_disabled(settings)
    try:
        yield
    finally:
        await retention.stop_periodic(purge_task)


def api_docs_urls(s: Settings) -> dict[str, str | None]:
    """API 문서 경로(#2834). 꺼져 있으면 셋 다 None — FastAPI 가 경로를 만들지 않아 404."""
    if s.api_docs_enabled:
        return {"docs_url": "/docs", "redoc_url": "/redoc", "openapi_url": "/openapi.json"}
    return {"docs_url": None, "redoc_url": None, "openapi_url": None}


app = FastAPI(
    title="On-Care Backend",
    description="PT 회원과 트레이너를 잇는 식단·운동 관리 서비스 — 회원 앱·트레이너 웹 공용 API",
    version=settings.app_version,
    lifespan=lifespan,
    **api_docs_urls(settings),
)


#: 표의 다른 규칙에 걸리지 않는 모든 요청의 본문 상한(#3238). 앱이 보내는 JSON 은 가장
#: 큰 것도 수십 KB 다 — 그 몇십 배를 두어 정상 요청은 걸리지 않고, 수백 MB 짜리 본문이
#: 메모리에 올라가 파싱되는 일만 막는다.
DEFAULT_MAX_BODY_BYTES = 1024 * 1024
#: 로그인·가입·refresh 등 무인증 `/auth/*` 경로의 본문 상한(#3238). 토큰 없이 누구나
#: 보낼 수 있는 경로라 가장 좁게 잡는다. 가장 큰 정상 본문(가입: 동의 목록 포함)도 수 KB 다.
AUTH_MAX_BODY_BYTES = 64 * 1024
#: 관리자 공공 문서 적재(`/coach/documents/public`) 본문 상한. 문서 원문을 JSON 으로
#: 받는 유일한 경로라 기본 상한에서 뺀다.
COACH_DOC_MAX_BODY_BYTES = 10 * 1024 * 1024
_BODY_TOO_LARGE = "요청이 너무 큽니다."


def body_limit_rules(s: Settings) -> tuple[BodyLimitRule, ...]:
    """경로별 요청 본문 상한 표(#2832). 처음 맞는 규칙 하나가 적용된다.

    파일을 받는 경로는 그 파일에 맞는 상한을 따로 둔다. 파일을 받는 새 라우트를
    만들면 여기에 더한다(`tests/test_upload_body_limit_guard.py`).

    맨 끝은 **모든 경로의 기본 상한**이다(#3238). 예전에는 업로드 경로에만 걸어
    `/auth/register`·`/auth/login`·`/auth/refresh` 같은 무인증 경로가 큰 본문을 그대로
    읽었다. 기본보다 큰 본문이 필요한 경로(관리자 문서 적재)만 위에서 따로 연다.
    """
    v1 = re.escape(s.api_v1_prefix)
    chat_image = s.max_chat_image_bytes + s.upload_body_slack_bytes
    report_pdf = s.max_report_pdf_bytes + s.upload_body_slack_bytes
    image_detail = (
        f"사진 용량이 너무 커요(최대 {s.max_chat_image_bytes // (1024 * 1024)}MB)."
    )
    return (
        # 식단 사진 분석. 값 자체가 multipart 여유를 포함한다(config 주석 참고).
        BodyLimitRule(f"{s.api_v1_prefix}/diet/analyze", s.max_upload_bytes),
        # 회원 AI 코치 채팅(#1549). 필드 제한(질문·history 길이)은 Pydantic 이 422 로
        # 거르지만, 그 전에 본문 전체를 메모리에 올리고 파싱한다 — 수 MB 짜리 JSON 은
        # 여기서 먼저 끊는다.
        BodyLimitRule(
            f"{s.api_v1_prefix}/ai-coach/chat",
            s.coach_chat_max_body_bytes,
            "요청이 너무 커요. 질문과 대화 기록을 줄여 다시 보내 주세요.",
        ),
        # 채팅 사진 — 회원 → 트레이너, 트레이너 → 회원.
        BodyLimitRule(
            rf"{v1}/me/coach/chat/image", chat_image, image_detail, regex=True
        ),
        BodyLimitRule(
            rf"{v1}/trainer/clients/[^/]+/chat/image",
            chat_image,
            image_detail,
            regex=True,
        ),
        # 주간 리포트 PDF.
        BodyLimitRule(
            rf"{v1}/trainer/clients/[^/]+/report/send-pdf",
            report_pdf,
            f"PDF 용량이 너무 커요(최대 {s.max_report_pdf_bytes // (1024 * 1024)}MB).",
            regex=True,
        ),
        # 관리자 공공 문서 적재 — 문서 원문을 JSON 본문으로 받는다.
        BodyLimitRule(
            f"{s.api_v1_prefix}/coach/documents/public",
            COACH_DOC_MAX_BODY_BYTES,
            _BODY_TOO_LARGE,
        ),
        # 무인증 경로(로그인·가입·refresh·소셜·비밀번호 재설정)는 가장 좁게.
        BodyLimitRule(f"{s.api_v1_prefix}/auth/", AUTH_MAX_BODY_BYTES, _BODY_TOO_LARGE),
        # 나머지 모든 경로의 기본 상한(#3238). 반드시 맨 끝이다 — 처음 맞는 규칙이 이긴다.
        BodyLimitRule("/", DEFAULT_MAX_BODY_BYTES, _BODY_TOO_LARGE),
    )


# 요청 본문 상한(413). add_middleware 는 나중에 추가한 것이 바깥에 감기므로, 이걸
# CORS 보다 먼저 등록해 CORS 가 바깥에 오게 한다 — 그래야 413 응답에도 CORS 헤더가
# 붙어서 웹 클라이언트가 상태코드를 읽을 수 있다. 경로마다 인스턴스를 따로 두지 않고
# 표 하나로 등록해 이 순서를 한 곳에서 지킨다(#2832).
app.add_middleware(RequestBodySizeLimitMiddleware, rules=body_limit_rules(settings))

# HTTPS 강제(운영). 프록시 뒤면 X-Forwarded-Proto 를 신뢰(uvicorn --proxy-headers).
# 로드 밸런서 헬스체크는 평문 HTTP 로 직접 들어오므로 /v1/healthz·/v1/readyz 는
# 리다이렉트하지 않는다(#3130, app/core/https_redirect.py).
https_redirect.install(app, settings)

# CORS: 와일드카드('*')면 자격증명(쿠키) 불가 → allow_credentials=False.
# 명시 출처면 자격증명 허용. (앱은 Bearer 토큰이라 와일드카드+무자격증명으로 충분.)
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origin_list,
    allow_credentials=not settings.is_cors_wildcard,
    allow_methods=["*"],
    allow_headers=["*"],
    # 트레이너 알림함 다음 쪽 커서(#2293). 노출하지 않으면 브라우저가 헤더를
    # 가려, 트레이너 웹은 늘 마지막 쪽이라고 읽는다.
    expose_headers=[
        trainer_notifications.NEXT_BEFORE_HEADER,
        trainer_notifications.NEXT_BEFORE_ID_HEADER,
    ],
)


# 보안 응답 헤더(운영/HTTPS 에서는 HSTS 포함).
if settings.security_headers:

    @app.middleware("http")
    async def _security_headers(request: Request, call_next):
        response = await call_next(request)
        # 값과 대상 경로는 app/core/security_headers.py 에 모았다(#2828).
        for name, value in security_headers_for(
            request.url.path, hsts=settings.is_prod or settings.force_https
        ).items():
            response.headers.setdefault(name, value)
        return response


# 클라이언트 종류(#2828): 웹 빌드가 보내는 `X-Client-Platform: web` 을 읽어, 웹 로그인·
# 회전에는 짧은 refresh 토큰을 준다(`services/auth_tokens.py`).
app.add_middleware(RequestClientPlatformMiddleware)


# 요청 언어(#2297): `Accept-Language` 를 읽어 `current_locale()` 을 채운다. 서버가 만드는
# 문장은 이 값으로 한국어·영어를 고른다(헤더가 없으면 한국어).
app.add_middleware(RequestLocaleMiddleware)


# 관측성: request-id 미들웨어(가장 바깥 — 컨텍스트를 먼저 세팅) + 액세스 로그 + 전역 500 핸들러.
# 보안 헤더 미들웨어 뒤에 설치해 request-id 미들웨어가 최외곽에서 감싸게 한다.
# 전역 500 핸들러는 CORS 바깥에서 돌므로 같은 출처 목록을 넘겨 CORS 헤더를 직접 붙인다(#3242).
observability.install(app, cors_origins=settings.cors_origin_list)

# 하루 AI 호출 상한(#3032) → 429 `daily_limit`(트레이너)·503 `ai_capacity`(서버 전체).
ai_call_errors.install(app)

# /v1 prefix 로 마운트 (프론트 base URL 이 /v1 을 포함하는 계약)
app.include_router(system.router, prefix=settings.api_v1_prefix)
app.include_router(users.router, prefix=settings.api_v1_prefix)
app.include_router(social.router, prefix=settings.api_v1_prefix)
app.include_router(dashboard.router, prefix=settings.api_v1_prefix)
app.include_router(diet.router, prefix=settings.api_v1_prefix)
app.include_router(exercise.router, prefix=settings.api_v1_prefix)
app.include_router(notifications.router, prefix=settings.api_v1_prefix)
app.include_router(places.router, prefix=settings.api_v1_prefix)
app.include_router(ai_coach.router, prefix=settings.api_v1_prefix)
app.include_router(chat_attachments.router, prefix=settings.api_v1_prefix)
app.include_router(coach_docs.router, prefix=settings.api_v1_prefix)
app.include_router(admin_trainers.router, prefix=settings.api_v1_prefix)
# 트레이너 라우터는 영역별로 나뉘어 있다(#2909) — 같은 prefix 로 정해진 순서대로 붙인다.
for trainer_router in trainer.routers:
    app.include_router(trainer_router, prefix=settings.api_v1_prefix)
app.include_router(member_coach.router, prefix=settings.api_v1_prefix)
app.include_router(points.router, prefix=settings.api_v1_prefix)
app.include_router(emotes.router, prefix=settings.api_v1_prefix)
# 연속 기록 보호권(#1788). 교환은 포인트 사용처(`points`)와 같은 경로다.
app.include_router(streak_shields.router, prefix=settings.api_v1_prefix)
# 기록 그래프와 그래프 색(#2075, #2076). 색을 여는 교환도 `points` 와 같은 경로다.
app.include_router(activity.router, prefix=settings.api_v1_prefix)
app.include_router(challenges.router, prefix=settings.api_v1_prefix)
app.include_router(consultations.router, prefix=settings.api_v1_prefix)
app.include_router(reservations.router, prefix=settings.api_v1_prefix)
# 회원앱 헬스장·트레이너 디렉터리(#324). trainer(단수, 트레이너 앱 전용)와 별개다.
app.include_router(gyms.router, prefix=settings.api_v1_prefix)
app.include_router(trainers.router, prefix=settings.api_v1_prefix)
