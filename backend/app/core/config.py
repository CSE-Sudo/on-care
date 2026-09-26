"""환경 설정. .env 에서 읽어옵니다."""
from __future__ import annotations

from functools import lru_cache
from typing import Literal

from pydantic import model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

# 개발 기본 시크릿(운영에서 그대로 쓰면 기동 차단)
DEFAULT_JWT_SECRET = "CHANGE_ME_dev_only_secret_key_please_replace_in_prod"
# 데모 계정(트레이너/회원 시드) 기본 로그인 비밀번호. 운영에서 데모 시드를 켜려면
# 반드시 이 기본값이 아닌 안전한 값으로 바꿔야 한다(아래 _guard_prod_secrets 가 강제).
DEFAULT_DEMO_PASSWORD = "oncare123"
# 운영에서 데모 시드를 켤 때 요구하는 DEMO_LOGIN_PASSWORD 최소 길이.
MIN_DEMO_PASSWORD_LEN = 12


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    # --- 환경 ---
    env: str = "dev"  # dev | staging | prod

    # --- API ---
    api_v1_prefix: str = "/v1"
    app_version: str = "0.4.0"

    # --- Database ---
    database_url: str = "postgresql+psycopg://oncare:oncare@localhost:5432/oncare"
    # DB 커넥션 인출(연결 수립) 상한(초) — 네트워크 파티션/무응답 시 스레드 무한 점유 방지.
    db_connect_timeout_seconds: int = 5
    # 앱 기동 시 create_all() 로 테이블 생성 여부(개발 편의). 운영은 Alembic 을 정답으로 → false 권장.
    auto_create_tables: bool = True

    # --- JWT ---
    jwt_secret: str = DEFAULT_JWT_SECRET
    jwt_algorithm: str = "HS256"
    access_token_expire_minutes: int = 60 * 24
    refresh_token_expire_days: int = 30
    # 토큰 없이 접근 시 데모 사용자로 폴백(개발 편의). 운영(prod)에서는 항상 비활성.
    allow_demo_fallback: bool = True

    # --- 소셜 로그인 ---
    # Apple 로그인에서 허용할 `aud`(client_id) 목록, 콤마 구분.
    # iOS 앱은 번들 ID, 웹은 Service ID 로 서로 다른 aud 를 받으므로 복수를 허용한다.
    # 비어 있으면 Apple 로그인은 검증 불가로 **거부**된다(조용히 통과시키면 다른 앱용
    # Apple 토큰으로도 로그인이 뚫린다).
    apple_client_ids: str = ""

    # --- 장소(O2O) ---
    # 카카오 Local REST 키. 있으면 실검색, 없으면 시드 폴백(recognizer 팩토리와 같은 철학).
    kakao_rest_api_key: str = ""
    # auto: 키 있으면 kakao, 없으면 seed. 강제하려면 kakao|seed.
    places_provider: Literal["auto", "kakao", "seed"] = "auto"
    kakao_timeout_seconds: float = 3.0

    # --- 업로드 ---
    # 업로드 엔드포인트의 요청 본문 상한(바이트). 적용 경로는 main.py 의
    # RequestBodySizeLimitMiddleware 에 명시한다(전역 아님 — 대량 텍스트를 JSON
    # 으로 받는 엔드포인트까지 묶이면 기능이 잘린다).
    #
    # 회원 앱은 사진을 1600px·품질 85 로 재인코딩하고 8MiB 를 넘으면 보내지
    # 않지만, 그건 앱의 UX 보호일 뿐 API 직접 호출은 막지 못한다. 여기가 최후
    # 방어선이다.
    #
    # 값이 앱의 이미지 상한(8MiB)보다 큰 것은 의도한 것이다 — 이 한도는 multipart
    # 경계·필드까지 포함한 '요청 본문' 크기라, 8MiB 로 맞추면 정확히 8MiB 인 사진이
    # 프레이밍 오버헤드 때문에 억울하게 413 을 맞는다.
    max_upload_bytes: int = 10 * 1024 * 1024
    # 주간 리포트 PDF는 일반 파일 첨부가 아니라 전용 endpoint만 사용한다.
    # DB에는 metadata만 두고 실제 파일은 이 디렉터리에 보관한다.
    report_pdf_storage_dir: str = "data/report-pdfs"
    max_report_pdf_bytes: int = 8 * 1024 * 1024

    #: 채팅 이미지 첨부(#921). PDF 와 다른 자리에 두는 이유는 지우는 주기가
    #: 다르기 때문이다 — 리포트 PDF 는 그 주의 산출물이고, 코칭 사진은 대화의
    #: 일부로 남는다.
    chat_image_storage_dir: str = "data/chat-images"
    #: 사진 한 장의 상한. 휴대폰 카메라 원본을 그대로 올려도 걸리지 않을
    #: 정도이되, 대화 스레드가 파일 서버가 되지는 않을 정도.
    max_chat_image_bytes: int = 6 * 1024 * 1024

    # --- AI 엔진 ---
    recognizer: str = "gemini"        # gemini | claude(litellm) | yolo
    # 인식 후 공공 식품영양성분 DB 로 영양 수치 보강(정확도↑). 순수 LLM 비교실험 시 false.
    nutrition_db_enrich: bool = True
    #: 참조표에 바로 붙지 않는 운동 이름을 AI 로 종목에 접는다(#1312). 끄면 표
    #: 매칭만 쓰고, 안 붙는 이름은 유형 평균으로 떨어진다 — 인식기와 같은 규약이라
    #: 키가 없으면 이 값과 무관하게 조용히 폴백한다.
    exercise_name_ai: bool = True
    gemini_api_key: str = ""
    gemini_model: str = "gemini-flash-latest"  # 챗·인식 공용. 핀 버전은 은퇴로 404 → latest 별칭 사용
    # Gemini HTTP 타임아웃(초). 걸지 않으면 무응답 시 호출 스레드가 무기한 묶여
    # 워커 풀이 고갈된다(추천 경로는 스레드 풀에서 돈다).
    gemini_timeout_seconds: float = 30.0
    coach_llm: str = "gemini"         # openai | gemini | litellm
    openai_api_key: str = ""
    openai_chat_model: str = "gpt-4o"
    embedder: str = "gemini"          # openai | gemini | litellm
    openai_embed_model: str = "text-embedding-3-small"

    # --- LiteLLM 프록시 (OpenAI 호환) ---
    # 하나의 Virtual Key 로 뒤의 여러 모델(claude 등)을 호출.
    # base_url 을 넣으면 OpenAI SDK 가 이 프록시를 바라봄.
    litellm_base_url: str = ""
    litellm_api_key: str = ""                       # Virtual Key
    litellm_chat_model: str = "claude-sonnet-4-6"   # 코치/인식용 채팅 모델
    litellm_embed_model: str = ""                   # 프록시에 임베딩 모델 있으면 지정
    litellm_vision_model: str = "claude-sonnet-4-6" # 식단 인식(이미지)용

    # --- RAG (STEP 7) ---
    # 임베딩 차원: 모델에 맞춰 바꿉니다. 바꾸면 재임베딩 필요(scripts/reembed).
    #   Gemini gemini-embedding-001        = 768 (현재 기본, EMBEDDER=gemini)
    #   OpenAI text-embedding-3-small/large = 1536 / 3072 (EMBEDDER=openai 시 EMBED_DIM=1536)
    embed_dim: int = 768
    # 청킹: 윈도우(문장 수)와 겹침(stride 보정). 최적값 찾으면 여기만 수정.
    chunk_window: int = 5      # 한 청크에 묶을 문장 수
    chunk_overlap: int = 1     # 청크 간 겹칠 문장 수
    # 검색: 개인 문서 / 공공 문서 각각 top-k
    retrieve_personal_k: int = 3
    retrieve_public_k: int = 3
    # 식단/운동/채팅 기록 시 개인 RAG 문서 자동 적재(코치가 내 최근 데이터를 검색하도록)
    rag_auto_ingest: bool = True
    # 시드 기록도 개인 문서로 적재할지 (#604). 데모 계정에서 회원 앱 AI 코치가
    # 시드된 식단·운동·대화를 근거로 답하게 한다. 멱등이라 최초 기동에서만 임베딩이
    # 돌지만, 실 임베딩 키로 처음 띄우면 그만큼 기동이 길어진다 — 끄고 싶으면 false.
    seed_rag_ingest: bool = True

    # --- 기타 ---
    cors_allow_origins: str = "http://localhost:3000,http://localhost:5173,http://127.0.0.1:3000"
    seed_demo_data: bool = True
    # 데모 계정(트레이너/회원 시드) 로그인 비밀번호. 운영에서 데모 계정에 데이터를 담아
    # 두고 싶으면 이 값을 안전하게 설정한다(기본값이면 운영 기동 차단).
    demo_login_password: str = DEFAULT_DEMO_PASSWORD
    # 관리자 이메일(콤마구분) — 기동 시 해당 사용자를 is_admin=True 로 승격
    admin_emails: str = ""

    # --- 운영 배포 하드닝 ---
    force_https: bool = False       # HTTP→HTTPS 리다이렉트(프록시 뒤면 X-Forwarded-Proto 신뢰)
    security_headers: bool = True   # 보안 응답 헤더(HSTS·nosniff·frame deny 등)
    # 루트 로거 레벨. 허용값만(임의 문자열 금지 — 오타로 로깅이 조용히 죽는 것 방지).
    log_level: Literal["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"] = "INFO"

    # --- Rate limit (인증 엔드포인트 브루트포스 방어) ---
    rate_limit_enabled: bool = True
    rate_limit_auth_per_minute: int = 10  # IP·엔드포인트당 분당 시도 한도
    # AI 코치 채팅 한도. 브루트포스 방어가 아니라 LLM 비용 가드라서 목적이 다르다.
    # 사람이 대화하는 속도로는 걸리지 않되, 폭주하는 클라이언트는 막는 값.
    coach_chat_per_minute: int = 20
    # AI 챗봇 하루 대화 한도(#2145). 분당 한도는 폭주하는 클라이언트를 막고, 이 값들은
    # 한 회원의 하루 비용을 묶는다. 무료를 다 쓰면 한 번에 `coach_chat_paid_cost` 포인트로
    # 하루 `coach_chat_paid_per_day` 번까지 더 보낸다. 날짜는 KST 로 센다.
    coach_chat_free_per_day: int = 5
    coach_chat_paid_cost: int = 50
    coach_chat_paid_per_day: int = 10
    # 트레이너 루틴 생성 한도. 채팅보다 낮게 잡는다 — 같은 LLM 비용에 회원 분석
    # 쿼리가 더 얹히고, 슬라이더·강도·메모를 바꿔 가며 "생성"을 연타하기 쉬운
    # UI 라 연타가 그대로 비용이 된다. 생성 왕복이 실측 3~6초라(#579) 사람이
    # 결과를 보고 조정하는 속도로는 분당 10회에 닿지 않는다.
    routine_options_per_minute: int = 10
    # 상담 요청 생성 한도(#1628). 트래픽이 아니라 **남에게 주는 피해**를 막는 정책이다
    # — 답을 기다리는 요청 하나가 트레이너 자리 하나를 최대 24시간 잠그고(#1873),
    # 신청·취소를 되풀이하면 트레이너 알림함이 찬다. 둘 다 DB 에서 세므로 재기동이나
    # 여러 인스턴스에도 값이 같다. 0 이면 그 한도를 끈다.
    # 동시에 답을 기다릴 수 있는 요청 수. 넘으면 409 `too_many_pending`.
    consultation_max_pending: int = 3
    # 24시간에 만들 수 있는 요청 수(취소·거절·만료 포함). 넘으면 429 + Retry-After.
    # 다른 한도와 같이 RATE_LIMIT_ENABLED=false 면 끈다.
    consultation_create_per_day: int = 10

    @property
    def admin_email_set(self) -> set[str]:
        return {e.strip().lower() for e in self.admin_emails.split(",") if e.strip()}

    @property
    def sqlalchemy_database_url(self) -> str:
        """SQLAlchemy 엔진용 DB URL(psycopg v3 드라이버를 명시).

        Railway/Neon/Supabase/Heroku 등 관리형 Postgres 는 DATABASE_URL 을
        `postgres://…` 또는 드라이버 없는 `postgresql://…` 로 준다. 이 프로젝트는
        psycopg **v3** 만 설치돼 있어(psycopg2 없음) bare `postgresql://` 는
        SQLAlchemy 가 기본값인 psycopg2 로 붙으려다 기동에 실패한다. 그래서 여기서
        psycopg v3 드라이버(`postgresql+psycopg://`)로 정규화해, 플랫폼이 준 URL 을
        그대로 붙여도 되게 한다(이미 +psycopg 이거나 postgres 계열이 아니면 그대로).
        """
        url = self.database_url
        if url.startswith("postgres://"):
            url = "postgresql://" + url[len("postgres://") :]
        if url.startswith("postgresql://"):
            url = "postgresql+psycopg://" + url[len("postgresql://") :]
        return url

    @property
    def cors_origin_list(self) -> list[str]:
        return [o.strip() for o in self.cors_allow_origins.split(",") if o.strip()]

    @property
    def is_cors_wildcard(self) -> bool:
        return "*" in self.cors_origin_list

    @property
    def is_prod(self) -> bool:
        return self.env.strip().lower() in ("prod", "production")

    @property
    def demo_fallback_enabled(self) -> bool:
        """데모 사용자 폴백 허용 여부 — 운영에서는 설정과 무관하게 항상 비활성."""
        return self.allow_demo_fallback and not self.is_prod

    @model_validator(mode="after")
    def _guard_prod_secrets(self) -> "Settings":
        """운영 환경에서 안전하지 않은 기본값을 쓰면 기동을 막는다(fail-fast)."""
        if self.is_prod:
            if not self.jwt_secret or self.jwt_secret == DEFAULT_JWT_SECRET:
                raise ValueError(
                    "운영(env=prod)에서는 JWT_SECRET 을 안전한 값으로 반드시 설정해야 합니다."
                )
            if self.is_cors_wildcard:
                raise ValueError(
                    "운영(env=prod)에서는 CORS 허용 출처를 명시해야 합니다(와일드카드 '*' 금지)."
                )
            # 운영에서 데모 시드를 켜면 트레이너/회원 데모 계정이 생성된다. 약한 비밀번호가
            # 그대로 운영 자격증명이 되는 것을 막는다: 기본값 금지 + 최소 길이 강제.
            # (빈 문자열·짧은 문자열·기본값 모두 거부. 원치 않으면 SEED_DEMO_DATA=false)
            if self.seed_demo_data:
                pw = self.demo_login_password or ""
                if pw == DEFAULT_DEMO_PASSWORD or len(pw) < MIN_DEMO_PASSWORD_LEN:
                    raise ValueError(
                        "운영(env=prod)에서 데모 시드(SEED_DEMO_DATA=true)를 켜려면 "
                        f"DEMO_LOGIN_PASSWORD 를 기본값이 아닌 {MIN_DEMO_PASSWORD_LEN}자 이상의 "
                        "안전한 값으로 설정해야 합니다(또는 SEED_DEMO_DATA=false)."
                    )
            # 운영은 Alembic 을 스키마의 유일한 변경 경로로 삼는다. create_all 이 켜져 있으면
            # ORM 정의만으로 테이블이 생겨 Alembic 이력과 어긋날 수 있으므로, 조용히 무시하지 않고
            # 기동을 거부한다(AUTO_CREATE_TABLES=false 를 명시하도록 강제).
            if self.auto_create_tables:
                raise ValueError(
                    "운영(env=prod)에서는 AUTO_CREATE_TABLES=false 로 두고 Alembic 을 스키마의 "
                    "유일한 소스로 삼아야 합니다."
                )
        return self


@lru_cache
def get_settings() -> Settings:
    return Settings()
