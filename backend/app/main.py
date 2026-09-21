"""
FastAPI 진입점 (STEP 1: 골격 재구성).

프론트 계약에 맞춰 /v1 prefix 로 라우터를 마운트합니다.
실행: uvicorn app.main:app --reload
문서: http://localhost:8000/docs
"""

from __future__ import annotations

from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware

from app.api.v1 import (
    activity,
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
from app.core import observability
from app.core.body_limit import RequestBodySizeLimitMiddleware
from app.core.config import get_settings
from app.db.init_db import init_db

settings = get_settings()
# 로깅을 먼저 설정(요청 ID 포함 포맷). 이후 모듈 로거들이 이 설정을 따른다.
observability.setup_logging(settings.log_level)


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    yield


app = FastAPI(
    title="On-Care Backend",
    description="PT 회원과 트레이너를 잇는 식단·운동 관리 서비스 — 회원 앱·트레이너 웹 공용 API",
    version=settings.app_version,
    lifespan=lifespan,
)

# 업로드 본문 상한. 파일을 받는 경로에만 건다 — 전역으로 걸면 대량 텍스트를
# JSON 본문으로 받는 엔드포인트(coach-docs 문서 적재 등)까지 같은 상한에 묶인다.
#
# add_middleware 는 나중에 추가한 것이 바깥에 감기므로, 이걸 CORS 보다 먼저
# 등록해 CORS 가 바깥에 오게 한다 — 그래야 413 응답에도 CORS 헤더가 붙어서
# 웹 클라이언트가 상태코드를 읽을 수 있다.
app.add_middleware(
    RequestBodySizeLimitMiddleware,
    max_bytes=settings.max_upload_bytes,
    protected_paths=(f"{settings.api_v1_prefix}/diet/analyze",),
)

# HTTPS 강제(운영). 프록시 뒤면 X-Forwarded-Proto 를 신뢰(uvicorn --proxy-headers).
if settings.force_https:
    from starlette.middleware.httpsredirect import HTTPSRedirectMiddleware

    app.add_middleware(HTTPSRedirectMiddleware)

# CORS: 와일드카드('*')면 자격증명(쿠키) 불가 → allow_credentials=False.
# 명시 출처면 자격증명 허용. (앱은 Bearer 토큰이라 와일드카드+무자격증명으로 충분.)
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origin_list,
    allow_credentials=not settings.is_cors_wildcard,
    allow_methods=["*"],
    allow_headers=["*"],
)


# 보안 응답 헤더(운영/HTTPS 에서는 HSTS 포함).
if settings.security_headers:

    @app.middleware("http")
    async def _security_headers(request: Request, call_next):
        response = await call_next(request)
        response.headers.setdefault("X-Content-Type-Options", "nosniff")
        response.headers.setdefault("X-Frame-Options", "DENY")
        response.headers.setdefault("Referrer-Policy", "no-referrer")
        if settings.is_prod or settings.force_https:
            response.headers.setdefault(
                "Strict-Transport-Security", "max-age=63072000; includeSubDomains"
            )
        return response


# 관측성: request-id 미들웨어(가장 바깥 — 컨텍스트를 먼저 세팅) + 액세스 로그 + 전역 500 핸들러.
# 보안 헤더 미들웨어 뒤에 설치해 request-id 미들웨어가 최외곽에서 감싸게 한다.
observability.install(app)

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
app.include_router(trainer.router, prefix=settings.api_v1_prefix)
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
