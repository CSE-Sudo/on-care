"""환경 설정. .env 에서 읽어옵니다."""
from __future__ import annotations

import re
from functools import lru_cache
from typing import Literal, Optional
from urllib.parse import urlsplit

from pydantic import Field, field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

from app.core.db_url import pooler_problem

# 개발 기본 시크릿(운영에서 그대로 쓰면 기동 차단)
DEFAULT_JWT_SECRET = "CHANGE_ME_dev_only_secret_key_please_replace_in_prod"
# 회원 앱 최소 지원 버전 형식(#3045). 빌드 번호(`+N`)·접미사 없이 숫자 세 자리만.
MIN_APP_VERSION_PATTERN = re.compile(r"^\d+\.\d+\.\d+$")
# 데모 계정(트레이너/회원 시드) 기본 로그인 비밀번호. 데모 시드는 운영(env=prod)에서
# 켤 수 없으므로(아래 _guard_prod_secrets, #2811) 로컬·데모 환경에서만 쓰인다.
DEFAULT_DEMO_PASSWORD = "oncare123"
# 운영 JWT 서명 키 최소 길이(바이트, #3029). HS256 은 키가 해시 출력(32바이트)보다
# 짧으면 안전 여유가 줄어든다. `openssl rand -hex 32`(64자)는 그대로 통과한다.
MIN_PROD_JWT_SECRET_BYTES = 32
# CORS 허용 출처 코드 기본값(로컬 개발용). 운영에서 이 값 그대로면 키를 빠뜨린 것이다.
DEFAULT_CORS_ALLOW_ORIGINS = "http://localhost:3000,http://localhost:5173,http://127.0.0.1:3000"
# 운영 CORS 출처에 있으면 안 되는 개발 호스트(#3029).
_LOCAL_CORS_HOSTS = ("localhost", "127.0.0.1", "[::1]")


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    # --- 환경 ---
    env: str = "dev"  # dev | staging | prod

    # --- API ---
    api_v1_prefix: str = "/v1"
    app_version: str = "0.4.0"
    # 회원 모바일 앱의 최소 지원 버전(#3045, `MAJOR.MINOR.PATCH`). 이보다 낮은 빌드는
    # 업데이트 화면만 보인다. 비우면 검사하지 않는다(기본·개발·데모). 스토어에 새 빌드가
    # 반영된 것을 확인한 뒤 올린다(docs/mobile_release.md).
    min_member_app_version: str = ""

    @field_validator("min_member_app_version")
    @classmethod
    def _check_min_member_app_version(cls, value: str) -> str:
        """잘못된 값으로 모든 회원이 막히지 않게 기동에서 형식을 확인한다."""
        value = value.strip()
        if value and not MIN_APP_VERSION_PATTERN.match(value):
            raise ValueError(
                "MIN_MEMBER_APP_VERSION 은 MAJOR.MINOR.PATCH 형식(예: 1.2.0)이어야 합니다."
            )
        return value

    # 이 이미지를 만든 커밋 SHA(#3029). 배포 워크플로가 `docker build --build-arg
    # GIT_SHA=…` 로 넣고 Dockerfile 이 같은 이름의 환경변수로 옮긴다. 로컬·테스트는
    # `unknown`. `/version`·`/healthz` 와 Sentry release 가 이 값을 쓴다.
    git_sha: str = "unknown"

    # --- Database ---
    # 비밀값(접속 비밀번호·키·DSN)은 `repr=False` 로 둔다(#3090) — 설정 객체를 로그·
    # 오류 화면·디버거에서 찍어도 값이 나오지 않는다. 타입은 `str` 그대로라 사용처는
    # 바뀌지 않는다(`SecretStr` 은 모든 사용처·테스트가 `.get_secret_value()` 를
    # 거쳐야 해 이번 범위에서 고르지 않았다).
    database_url: str = Field(
        "postgresql+psycopg://oncare:oncare@localhost:5432/oncare", repr=False
    )
    # DB 커넥션 인출(연결 수립) 상한(초) — 네트워크 파티션/무응답 시 스레드 무한 점유 방지.
    db_connect_timeout_seconds: int = 5
    # 커넥션 풀(#2836). 기본값을 SQLAlchemy 에 맡기면 풀 대기가 30초라, 풀이 마르면
    # 가벼운 조회도 30초 뒤에 500 이 된다. 짧게 실패시켜 클라이언트 재시도로 넘긴다.
    # (pool_size + max_overflow) × 워커 수 × 인스턴스 수가 DB 연결 상한(Neon 플랜)
    # 안에 들어와야 한다 — 값은 배포 문서(DEPLOY.md)에 계산법과 함께 적어 둔다.
    db_pool_size: int = 5
    db_max_overflow: int = 10
    db_pool_timeout_seconds: float = 10.0
    # 유휴 연결 재활용 주기(초). 관리형 DB 가 오래 쉰 연결을 먼저 끊으면 다음 요청이
    # 끊긴 연결을 받는다(pre_ping 이 잡지만 왕복이 하나 더 든다). 그보다 짧게 둔다.
    db_pool_recycle_seconds: int = 300
    # 쿼리 하나의 실행 상한(ms). 잘못된 쿼리·잠금 대기 하나가 연결을 무기한 쥐지
    # 않게 한다. 0 이면 끈다. 마이그레이션(`scripts/migrate.py`·Alembic)은 별도
    # 연결이라 이 값의 영향을 받지 않는다.
    db_statement_timeout_ms: int = 10_000
    # 앱 기동 시 create_all() 로 테이블 생성 여부(개발 편의). 운영은 Alembic 을 정답으로 → false 권장.
    auto_create_tables: bool = True

    # --- JWT ---
    jwt_secret: str = Field(DEFAULT_JWT_SECRET, repr=False)
    jwt_algorithm: str = "HS256"
    # 접근 토큰 수명(#2913). 두 앱 모두 401 을 받으면 refresh 로 새 토큰을 받아 요청을
    # 다시 보내므로 짧아도 사용자 체감이 없고, 새어 나간 토큰이 쓰일 수 있는 시간이
    # 줄어든다. 데모·개발 환경은 ACCESS_TOKEN_EXPIRE_MINUTES 로 길게 둘 수 있다.
    access_token_expire_minutes: int = 60
    refresh_token_expire_days: int = 30
    # 웹 클라이언트(`X-Client-Platform: web`)가 받는 refresh 토큰 수명(#2828). 웹은
    # 토큰을 탭 단위 저장소에만 두므로 오래 갈 필요가 없고, 브라우저에서 새어 나갔을
    # 때 쓸 수 있는 기간을 줄인다. 모바일은 위 값을 그대로 쓴다.
    web_refresh_token_expire_days: int = 7
    # 로그인 한 번이 이어질 수 있는 최대 기간(#3086). refresh 토큰은 회전할 때마다 위
    # 수명을 새로 받으므로, 최초 로그인 시각(`auth_time`) 기준 상한이 없으면 손에 넣은
    # 토큰을 주기적으로 회전해 세션을 끝없이 이어 갈 수 있다. 넘으면 다시 로그인한다.
    session_max_days: int = 90
    web_session_max_days: int = 30
    # 회전으로 폐기된 refresh 토큰이 이 시간(초) 안에 다시 오면 동시 갱신(웹 탭 두 개,
    # 응답 전에 앱이 꺼진 경우)으로 보고 그 요청만 거부한다. 넘으면 탈취로 보고 그
    # 세션 전체를 끊는다(#3086).
    refresh_reuse_grace_seconds: int = 30
    # 토큰 없이 접근 시 데모 사용자로 폴백(개발 편의). 운영(prod)에서는 항상 비활성.
    # 기본은 꺼짐(#2821) — ENV 를 빠뜨린 채 뜬 서버가 로그인 없는 요청을 데모 회원으로
    # 처리하지 않게 한다. 로컬 개발은 .env.example 의 ALLOW_DEMO_FALLBACK=true 로 켠다.
    allow_demo_fallback: bool = False

    # --- 감사 로그 (#2830) ---
    # 트레이너의 회원 기록 열람(`trainer.client_read`)은 같은 (트레이너, 회원, 자원)
    # 조합을 이 시간(분) 안에 한 번만 남긴다 — 화면을 넘길 때마다 쌓이지 않게.
    audit_read_dedupe_minutes: int = 10
    # 보존 기간(일). 지난 기록은 기동 시 정리한다. 0 이면 정리하지 않는다.
    # 인증·계정 이벤트(접속 기록)는 1년, 건강정보 열람·동의·탈퇴 기록은 2년.
    audit_retention_days: int = 365
    audit_sensitive_retention_days: int = 730

    # --- 소셜 로그인 ---
    # Apple 로그인에서 허용할 `aud`(client_id) 목록, 콤마 구분.
    # iOS 앱은 번들 ID, 웹은 Service ID 로 서로 다른 aud 를 받으므로 복수를 허용한다.
    # 비어 있으면 Apple 로그인은 검증 불가로 **거부**된다(조용히 통과시키면 다른 앱용
    # Apple 토큰으로도 로그인이 뚫린다).
    apple_client_ids: str = ""
    # Google 로그인에서 허용할 id_token `aud`(OAuth client_id) 목록, 콤마 구분 (#3035).
    # iOS·Android·Web client_id 가 서로 다르므로 복수를 허용한다. 비어 있으면 Google
    # 로그인은 **거부**된다 — aud 를 보지 않으면 다른 앱이 받은 구글 토큰으로도 로그인된다.
    google_client_ids: str = ""
    # 카카오 로그인에서 허용할 앱 ID(카카오 개발자 콘솔 > 앱 설정의 숫자 "앱 ID") (#3035).
    # access_token 의 발급 앱(`/v1/user/access_token_info` 의 app_id)과 같아야 한다.
    # 장소 검색용 KAKAO_REST_API_KEY 와 다른 값이다. 비어 있으면 카카오 로그인은 거부된다.
    kakao_app_id: str = ""

    # --- 장소(O2O) ---
    # 카카오 Local REST 키. 있으면 실검색, 없으면 시드 폴백(recognizer 팩토리와 같은 철학).
    kakao_rest_api_key: str = Field("", repr=False)
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
    #: 채팅 사진·리포트 PDF 경로의 **요청 본문** 상한은 파일 상한에 이만큼을 더한
    #: 값이다(#2832). multipart 경계·메시지 필드·client_request_id 가 함께 실려 오므로,
    #: 파일 상한과 똑같이 두면 상한에 딱 맞는 파일이 413 을 맞는다. 파일 자체의
    #: 상한은 핸들러가 바이트를 세어 따로 지킨다.
    upload_body_slack_bytes: int = 512 * 1024
    #: 업로드 사진을 펼칠 때의 상한(#3040). 바이트 상한은 압축된 크기라 펼친 메모리를
    #: 막지 못한다 — 수백 KB 짜리 PNG 가 1억 픽셀일 수 있다. 픽셀 수는 실제로 펼칠
    #: 크기(JPEG 은 축소 디코딩 뒤)에, 장변은 원본 헤더 크기에 건다. 두 앱은 장변
    #: 1600px 로 줄여 보내므로 정상 경로는 이 값보다 훨씬 아래다.
    max_image_decode_pixels: int = 40_000_000
    max_image_decode_edge: int = 12_000

    #: 채팅 첨부(사진·리포트 PDF) 바이트 저장소(#2817). auto 는 버킷 이름이 있으면
    #: s3, 없으면 local(위 두 디렉터리). 컨테이너 디스크는 재배포·스케일 아웃에서
    #: 비므로 운영은 s3 를 쓴다. 자격 증명은 실행 환경의 IAM 역할에서 받는다.
    attachment_storage: Literal["auto", "local", "s3"] = "auto"
    attachment_s3_bucket: str = ""
    attachment_s3_region: str = ""
    #: 키 접두사. 실제 키는 `<접두사>/chat-images/<id>.<ext>`·`.../report-pdfs/<id>.pdf`.
    attachment_s3_prefix: str = "chat-attachments"
    #: S3 호환 저장소·로컬 에뮬레이터를 쓸 때만. 비우면 AWS 기본 엔드포인트.
    attachment_s3_endpoint_url: str = ""

    # --- AI 엔진 ---
    recognizer: str = "gemini"        # gemini | claude(litellm) | yolo
    # 인식 후 공공 식품영양성분 DB 로 영양 수치 보강(정확도↑). 순수 LLM 비교실험 시 false.
    nutrition_db_enrich: bool = True
    #: 참조표에 바로 붙지 않는 운동 이름을 AI 로 종목에 접는다(#1312). 끄면 표
    #: 매칭만 쓰고, 안 붙는 이름은 유형 평균으로 떨어진다 — 인식기와 같은 규약이라
    #: 키가 없으면 이 값과 무관하게 조용히 폴백한다.
    exercise_name_ai: bool = True
    gemini_api_key: str = Field("", repr=False)
    gemini_model: str = "gemini-flash-latest"  # 챗·인식 공용. 핀 버전은 은퇴로 404 → latest 별칭 사용
    # Gemini HTTP 타임아웃(초). 걸지 않으면 무응답 시 호출 스레드가 무기한 묶여
    # 워커 풀이 고갈된다(추천 경로는 스레드 풀에서 돈다).
    gemini_timeout_seconds: float = 30.0
    # LLM 한 번의 출력 토큰 상한(#3032). 호출처는 필요한 길이(한 문장 조언·JSON 후보
    # 등)에 맞춰 이보다 작게 넘기고, 넘기지 않는 호출(AI 코치 답변)은 이 값을 쓴다.
    # Gemini 는 사고 토큰도 이 안에서 쓰므로 너무 작게 잡으면 답이 비거나 잘린다.
    # 잘린 JSON 응답은 계약 위반으로 보고 규칙형 폴백을 탄다. 0 이면 상한을 넘기지 않는다.
    llm_max_output_tokens: int = 4096
    # 식단 사진 인식 HTTP 타임아웃(초, #2912). 사진 분석은 글 응답보다 오래 걸려
    # gemini_timeout_seconds 와 따로 둔다. Gemini·LiteLLM 비전 인식기가 함께 쓴다.
    recognizer_timeout_seconds: float = 60.0
    coach_llm: str = "gemini"         # openai | gemini | litellm
    openai_api_key: str = Field("", repr=False)
    openai_chat_model: str = "gpt-4o"
    embedder: str = "gemini"          # openai | gemini | litellm
    openai_embed_model: str = "text-embedding-3-small"

    # --- LiteLLM 프록시 (OpenAI 호환) ---
    # 하나의 Virtual Key 로 뒤의 여러 모델(claude 등)을 호출.
    # base_url 을 넣으면 OpenAI SDK 가 이 프록시를 바라봄.
    litellm_base_url: str = ""
    litellm_api_key: str = Field("", repr=False)  # Virtual Key
    litellm_chat_model: str = "claude-sonnet-4-6"   # 코치/인식용 채팅 모델
    litellm_embed_model: str = ""                   # 프록시에 임베딩 모델 있으면 지정
    litellm_vision_model: str = "claude-sonnet-4-6" # 식단 인식(이미지)용

    # --- RAG ---
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

    # --- 메일 발송(비밀번호 재설정, #2824) ---
    # auto: SMTP_HOST 와 MAIL_FROM 이 있으면 smtp, 없으면 log. log 는 실제로 보내지
    # 않고 서버 로그에만 남긴다(개발용). 운영에서 log 로 풀리면 재설정 요청은 503 으로
    # 꺼지고 기동 로그에 오류가 남는다(`mail_enabled`).
    # AWS SES 는 SMTP 인터페이스를 주므로 SES 도 이 smtp 구현으로 쓴다 — 계정·키는
    # 배포 환경변수로만 넣는다(코드·저장소에 두지 않는다).
    mail_provider: Literal["auto", "smtp", "log"] = "auto"
    mail_from: str = ""
    smtp_host: str = ""
    smtp_port: int = 587
    smtp_username: str = ""
    smtp_password: str = Field("", repr=False)
    # true: 평문 연결 뒤 STARTTLS(587). false 면 smtp_ssl 을 본다.
    smtp_starttls: bool = True
    # true: 처음부터 TLS(465). starttls 와 함께 켜면 ssl 이 우선한다.
    smtp_ssl: bool = False
    smtp_timeout_seconds: float = 10.0
    # 메일 끝에 적는 문의처(#3038·#3039). 비어 있으면 문의 줄을 넣지 않는다.
    # 발송 업체(SMTP/SES)·발신 주소(MAIL_FROM)와 함께 팀이 정할 값이다 — 메일 관련
    # 팀 결정 값은 이 절에만 둔다.
    mail_support_contact: str = ""

    # --- 가입 이메일 확인(#3038) ---
    # 회원·트레이너 가입 전에 그 주소로 보낸 6자리 코드를 확인한다. 끄면 가입이 코드를
    # 보지 않는다 — 기존 테스트·E2E(로그 발송)용이며, 운영(env=prod)에서는 끌 수 없다.
    signup_email_verification: bool = True
    # 코드 유효 시간(분)과 다시 받기까지 기다리는 시간(초).
    signup_email_code_minutes: int = 10
    signup_email_code_resend_seconds: int = 60
    # 한 코드로 틀릴 수 있는 횟수. 6자리라 이 값이 경우의 수를 묶는 유일한 장치다.
    signup_email_code_max_attempts: int = 5
    # 같은 이메일로 코드를 보낼 수 있는 횟수(아래 창 안에서). IP 버킷과 별개다 — 여러
    # IP 에서 한 사람에게 메일 폭탄을 보내는 것을 막는다.
    signup_email_code_per_window: int = 5
    signup_email_code_window_minutes: int = 60

    # --- 비밀번호 재설정(#2824) ---
    # 재설정 코드 유효 시간(분). 메일을 열어 바로 쓰는 일회용이라 짧게 둔다.
    password_reset_token_minutes: int = 30
    # 같은 이메일로 재설정 메일을 보낼 수 있는 횟수(아래 창 안에서). IP 버킷과 별개다
    # — 여러 IP 에서 한 사람에게 메일 폭탄을 보내는 것을 막는다.
    password_reset_email_per_window: int = 3
    password_reset_email_window_minutes: int = 15
    # 메일 속 링크가 여는 화면 주소. 비어 있으면 링크 없이 코드만 보낸다 — 앱에서
    # 코드를 붙여 넣어도 된다. `?token=` 이 붙는다.
    password_reset_member_url: str = ""
    password_reset_trainer_url: str = ""

    # --- 기타 ---
    cors_allow_origins: str = DEFAULT_CORS_ALLOW_ORIGINS
    # 데모 시드(데모 계정·회원 기록·가상 트레이너·가상 헬스장). 기본은 끔이다(#2811) —
    # 환경변수를 빠뜨린 채 띄운 서버가 데모 데이터를 심지 않도록. 로컬은 `.env.example`
    # 에서 명시적으로 켠다. 운영(env=prod)에서는 켤 수 없다(아래 가드).
    seed_demo_data: bool = False
    # 데모 계정(트레이너/회원 시드) 로그인 비밀번호. 데모 시드를 켠 환경에서만 쓰인다.
    demo_login_password: str = Field(DEFAULT_DEMO_PASSWORD, repr=False)
    # 헬스장 현장 혜택(PT 재등록 할인·락커 쿠폰·분석용 식판)을 실제로 열지(#2822).
    # 제휴 헬스장이 없는 동안은 꺼 둔다. 데모 시드가 켜진 서버는 이 값과 상관없이 연다.
    gym_benefits_enabled: bool = False
    # 예전 관리자 이메일 목록. 기동 때 이 주소의 계정을 관리자로 올리던 동작은 없앴다
    # (#3037) — 그 주소로 먼저 가입한 사람이 관리자가 됐다. 관리자 지정은
    # `scripts/grant_admin.py` 로만 한다. 값이 남아 있으면 기동 로그가 경고한다.
    admin_emails: str = ""

    # --- 운영 배포 하드닝 ---
    force_https: bool = False       # HTTP→HTTPS 리다이렉트(프록시 뒤면 X-Forwarded-Proto 신뢰)
    security_headers: bool = True   # 보안 응답 헤더(HSTS·nosniff·frame deny 등)
    # 루트 로거 레벨. 허용값만(임의 문자열 금지 — 오타로 로깅이 조용히 죽는 것 방지).
    log_level: Literal["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"] = "INFO"

    # --- 에러 추적(Sentry, #2839) ---
    # 처리하지 못한 예외를 외부 에러 추적 도구로 보낸다. DSN 은 배포 환경변수로만 넣고
    # 저장소에 두지 않는다. 비어 있거나 ENV=dev 면 초기화하지 않는다(개발·데모 오류는
    # 보내지 않음). 요청 본문·헤더·쿼리·지역 변수는 보내지 않는다(app/core/error_tracking.py).
    sentry_dsn: str = Field("", repr=False)
    # 비우면 ENV 값(staging·prod)을 그대로 쓴다.
    sentry_environment: str = ""
    # 오류 이벤트 표본 비율(0~1). 성능 추적(APM)은 켜지 않는다.
    sentry_sample_rate: float = Field(default=1.0, ge=0.0, le=1.0)

    # --- Rate limit (인증 엔드포인트 브루트포스 방어) ---
    rate_limit_enabled: bool = True
    rate_limit_auth_per_minute: int = 10  # IP·엔드포인트당 분당 시도 한도
    # AI 코치 채팅 한도. 브루트포스 방어가 아니라 LLM 비용 가드라서 목적이 다르다.
    # 사람이 대화하는 속도로는 걸리지 않되, 폭주하는 클라이언트는 막는 값.
    # 회원 AI 코치(IP 버킷)와 트레이너 고객 AI 코치(트레이너 id 버킷, #1548)가 같이 쓴다.
    coach_chat_per_minute: int = 20
    # 회원 AI 코치 요청 본문 상한(#1549, 413). 필드 제한(질문 1000자·history 20턴×2000자)을
    # 다 채운 정상 요청이 JSON 이스케이프(`\uXXXX`, 글자당 6바이트)로 보내져도 들어가는 값.
    # 필드 검증보다 앞에서, 본문을 읽는 도중에 끊는다.
    coach_chat_max_body_bytes: int = 256 * 1024
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
    # 식단 사진 분석 한도(#2827). 사진 한 장이 외부 비전 모델 호출 한 번이라 비용이
    # 가장 큰 축이다. 분당 값은 재시도 루프·스크립트 폭주를 막고(사용자 id 버킷 —
    # 같은 헬스장 Wi-Fi 의 회원끼리 한 버킷을 나눠 쓰지 않게), 하루 값은 한 회원의
    # 하루 비용을 묶는다. 하루 값은 DB(`diet_analysis_usages`)에서 KST 날짜로 세므로
    # 재기동·여러 인스턴스에서도 같다. 끼니 다섯 번에 재촬영 여유를 더한 값이다.
    # 0 이면 그 한도를 끈다. RATE_LIMIT_ENABLED=false 면 둘 다 끈다.
    diet_analyze_per_minute: int = 10
    diet_analyze_per_day: int = 20
    # 서버 전체·트레이너 계정의 하루 AI 호출 상한(#3032). 위 값들은 **한 회원**을
    # 묶을 뿐이라, 가입자가 늘면 그 합만큼 비용이 열린다. 두 값 모두 DB
    # (`ai_call_usages`)에서 KST 날짜로 세므로 재기동·워커 수·인스턴스 수와 상관없이
    # 같다. 0 이면 그 상한을 끈다. RATE_LIMIT_ENABLED=false 면 둘 다 끈다.
    # - 전역: 외부 LLM·비전 모델을 실제로 부르는 모든 기능의 합. 넘으면 규칙형 폴백이
    #   있는 기능은 폴백으로, 없는 기능(AI 코치 채팅·사진 분석)은 503 `ai_capacity` 로
    #   답한다. 기본값 0(끔) — 운영 값은 배포 설정에서 정한다(DEPLOY.md 3절).
    # - 트레이너: 한 트레이너 계정의 고객 AI 코치·루틴 후보·리포트 요약 합. 넘으면
    #   429 `daily_limit` + `Retry-After`(KST 자정까지). 공개 가입 계정 하나가 분당
    #   한도 안에서 하루 종일 부르는 것을 막는다.
    ai_global_calls_per_day: int = 0
    trainer_ai_calls_per_day: int = 200
    # 상담 요청 생성 한도(#1628). 트래픽이 아니라 **남에게 주는 피해**를 막는 정책이다
    # — 답을 기다리는 요청 하나가 트레이너 자리 하나를 최대 24시간 잠그고(#1873),
    # 신청·취소를 되풀이하면 트레이너 알림함이 찬다. 둘 다 DB 에서 세므로 재기동이나
    # 여러 인스턴스에도 값이 같다. 0 이면 그 한도를 끈다.
    # 동시에 답을 기다릴 수 있는 요청 수. 넘으면 409 `too_many_pending`.
    consultation_max_pending: int = 3
    # 24시간에 만들 수 있는 요청 수(취소·거절·만료 포함). 넘으면 429 + Retry-After.
    # 다른 한도와 같이 RATE_LIMIT_ENABLED=false 면 끈다.
    consultation_create_per_day: int = 10
    # 같은 이메일 로그인 연속 실패 잠금(#2815). IP 를 바꿔 가며 한 계정의 비밀번호를
    # 맞혀 보는 것을 막는다 — IP 한도만으로는 요청마다 주소를 바꾸면 끝없이 시도할 수
    # 있다. `login_lockout_seconds` 안에 `login_max_failures` 번 틀리면 그 이메일은
    # 남은 시간 동안 429 다. 성공하면 실패 기록을 지운다.
    login_max_failures: int = 5
    login_lockout_seconds: int = 15 * 60
    # 회원 연결 코드 미리보기·사용의 트레이너 하루 상한(#2815). 분당 한도(IP·트레이너
    # id)에 더해, 트레이너 계정이 공개 가입이라 한 계정이 하루 종일 코드를 훑는 것을
    # 막는다. 정상 사용(회원 한 명당 한두 번)으로는 닿지 않는 값.
    pairing_redeem_per_day: int = 30
    # 같은 이메일 가입 시도의 시간당 상한(#2913). 가입은 이미 있는 이메일에 409 를
    # 주므로, IP 한도만으로는 IP 를 바꿔 가며 특정 이메일의 가입 여부를 계속 물을 수
    # 있다. 회원·트레이너 가입이 한 버킷을 쓴다. 정상 가입(오타 몇 번)으로는 닿지 않는 값.
    register_per_email_per_hour: int = 5
    # 비밀번호 변경의 현재 비밀번호 연속 실패 잠금(#2913). 접근 토큰을 손에 넣은 쪽이
    # 현재 비밀번호를 맞혀 보는 것을 사용자 id 단위로 막는다. 창은 로그인 잠금과 같다
    # (`login_lockout_seconds`).
    password_change_max_failures: int = 5

    # --- 클라이언트 IP (#2815) ---
    # rate limit 키·감사 로그 IP 를 정할 때 믿는 앞단 프록시 수. `X-Forwarded-For` 를
    # 오른쪽에서 이 번째 값으로 읽는다(`app/core/client_ip.py`). 0 이면 헤더를 보지 않고
    # 소켓 주소를 쓴다. 비워 두면 운영(prod)은 1, 그 밖은 0 — 운영 배포(ECS Express Mode
    # 의 ALB·Railway·EC2+Nginx)는 모두 프록시 하나 뒤다. 프록시가 늘면 그 수로 맞춘다.
    trusted_proxy_hops: Optional[int] = Field(default=None, ge=0, le=5)

    @property
    def effective_proxy_hops(self) -> int:
        """실제로 쓰는 신뢰 프록시 홉 수(미설정이면 운영 1, 그 밖 0)."""
        if self.trusted_proxy_hops is not None:
            return self.trusted_proxy_hops
        return 1 if self.is_prod else 0

    #: API 문서(`/docs`·`/redoc`·`/openapi.json`) 공개 여부(#2834). 비워 두면 운영은
    #: 끄고 그 밖은 켠다. 문서는 엔드포인트 전체 목록·스키마·docstring 의 내부 설계
    #: 설명을 인증 없이 보여 준다 — 운영 스키마는 스테이징·로컬에서 본다. 꼭 운영에서
    #: 켜야 하면 `EXPOSE_API_DOCS=true` 로 명시한다.
    expose_api_docs: Optional[bool] = None

    @property
    def api_docs_enabled(self) -> bool:
        """실제로 문서를 여는가(미설정이면 운영 끔, 그 밖 켬)."""
        if self.expose_api_docs is not None:
            return self.expose_api_docs
        return not self.is_prod

    @property
    def apple_client_id_list(self) -> list[str]:
        """허용 Apple `aud` 목록(공백·빈 항목 제거)."""
        return _comma_list(self.apple_client_ids)

    @property
    def google_client_id_list(self) -> list[str]:
        """허용 Google `aud` 목록(공백·빈 항목 제거)."""
        return _comma_list(self.google_client_ids)

    @property
    def kakao_app_id_value(self) -> str:
        """허용 카카오 앱 ID(앞뒤 공백 제거, 미설정이면 빈 문자열)."""
        return (self.kakao_app_id or "").strip()

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
    def commit_sha(self) -> str:
        """응답에 싣는 커밋 SHA. 비었거나 공백이면 `unknown`."""
        return self.git_sha.strip() or "unknown"

    def cors_prod_problem(self) -> str | None:
        """운영 CORS 출처 목록의 문제(#3029). 문제가 없으면 None.

        와일드카드는 따로 막는다(`_guard_prod_secrets`). 여기서는 키를 빠뜨려 개발
        기본값으로 뜬 경우, 개발 호스트·평문 HTTP 출처가 섞인 경우, 목록이 빈 경우를 본다.
        """
        origins = self.cors_origin_list
        if not origins:
            return "CORS_ALLOW_ORIGINS 가 비어 있음"
        if origins == [o.strip() for o in DEFAULT_CORS_ALLOW_ORIGINS.split(",")]:
            return "CORS_ALLOW_ORIGINS 가 개발 기본값(localhost 목록) 그대로임"
        for origin in origins:
            if origin == "*":
                continue
            parts = urlsplit(origin.lower())
            if parts.scheme != "https" or not parts.netloc:
                return f"CORS 출처 {origin!r} 가 https:// 가 아님"
            # urlsplit 은 IPv6 대괄호를 벗긴다 — 비교 목록과 같은 모양으로 되돌린다.
            hostname = parts.hostname or ""
            if ":" in hostname:
                hostname = f"[{hostname}]"
            if hostname in _LOCAL_CORS_HOSTS:
                return f"CORS 출처 {origin!r} 가 개발 호스트임"
        return None

    @property
    def is_prod(self) -> bool:
        return self.env.strip().lower() in ("prod", "production")

    @property
    def mail_backend(self) -> str:
        """실제로 쓸 메일 발송 수단(`smtp`|`log`). `auto` 를 여기서 푼다."""
        if self.mail_provider != "auto":
            return self.mail_provider
        return "smtp" if self.smtp_host.strip() and self.mail_from.strip() else "log"

    @property
    def mail_enabled(self) -> bool:
        """재설정 메일을 보낼 수 있는가.

        개발·스테이징은 log 발송으로도 켜 둔다(코드를 서버 로그에서 읽어 확인한다).
        운영은 실제 발송 수단이 있어야만 켠다 — 로그로만 남기는 재설정은 회원에게
        닿지 않을뿐더러, 로그를 읽을 수 있는 사람이 남의 계정을 되찾게 된다.
        """
        if self.mail_backend == "smtp":
            return bool(self.smtp_host.strip() and self.mail_from.strip())
        return not self.is_prod

    @property
    def demo_fallback_enabled(self) -> bool:
        """데모 사용자 폴백 허용 여부 — 운영에서는 설정과 무관하게 항상 비활성."""
        return self.allow_demo_fallback and not self.is_prod

    @model_validator(mode="after")
    def _guard_prod_secrets(self) -> "Settings":
        """운영 환경에서 안전하지 않은 기본값을 쓰면 기동을 막는다(fail-fast)."""
        # SMTP 를 명시해 놓고 서버·발신 주소를 비우면 설정 실수다. auto 와 달리 조용히
        # log 로 떨어뜨리지 않고 기동에서 드러낸다(#2824).
        if self.mail_provider == "smtp" and not (
            self.smtp_host.strip() and self.mail_from.strip()
        ):
            raise ValueError(
                "MAIL_PROVIDER=smtp 이면 SMTP_HOST 와 MAIL_FROM 을 함께 설정해야 합니다."
            )
        if self.is_prod:
            if not self.jwt_secret or self.jwt_secret == DEFAULT_JWT_SECRET:
                raise ValueError(
                    "운영(env=prod)에서는 JWT_SECRET 을 안전한 값으로 반드시 설정해야 합니다."
                )
            # 개발 기본값만 아니면 `abc` 도 통과하던 빈틈(#3029).
            if len(self.jwt_secret.encode("utf-8")) < MIN_PROD_JWT_SECRET_BYTES:
                raise ValueError(
                    f"운영(env=prod)에서는 JWT_SECRET 이 {MIN_PROD_JWT_SECRET_BYTES}바이트 이상이어야 "
                    "합니다(예: openssl rand -hex 32)."
                )
            if self.is_cors_wildcard:
                raise ValueError(
                    "운영(env=prod)에서는 CORS 허용 출처를 명시해야 합니다(와일드카드 '*' 금지)."
                )
            # 키를 빠뜨리면 localhost 목록으로 떠서 운영 프론트 요청이 브라우저에서 모두
            # 막힌다. 조용히 뜨지 않고 기동에서 드러낸다(#3029).
            cors_problem = self.cors_prod_problem()
            if cors_problem:
                raise ValueError(
                    "운영(env=prod)에서는 CORS 허용 출처를 실제 프론트 도메인(https://)으로 "
                    f"설정해야 합니다: {cors_problem}"
                )
            # 운영 DB 에 데모 데이터(가상 트레이너·데모 회원 기록)가 섞이면 회원 앱
            # 트레이너 찾기에 실존하지 않는 사람이 노출되고 통계가 오염된다(#2811).
            # 비밀번호 강도와 상관없이 막는다 — 시연이 필요하면 데모 전용 DB 를 쓴다.
            # 가입 이메일 확인을 끄면 남의 이메일로 계정을 선점할 수 있다(#3038).
            if not self.signup_email_verification:
                raise ValueError(
                    "운영(env=prod)에서는 가입 이메일 확인을 끌 수 없습니다"
                    "(SIGNUP_EMAIL_VERIFICATION=true)."
                )
            if self.seed_demo_data:
                raise ValueError(
                    "운영(env=prod)에서는 데모 시드를 켤 수 없습니다(SEED_DEMO_DATA=false). "
                    "시연은 데모 전용 DB 를 둔 별도 환경에서 하십시오."
                )
            # Neon 풀러(트랜잭션 풀링) 주소면 마이그레이션 잠금이 동작하지 않고 연결 시작
            # 옵션이 거절된다(#3146). 원인을 알기 어려운 실패 대신 기동에서 막는다.
            db_problem = pooler_problem(self.database_url)
            if db_problem:
                raise ValueError(f"운영(env=prod)에서는 직접 DB 엔드포인트를 써야 합니다: {db_problem}")
            # 운영은 Alembic 을 스키마의 유일한 변경 경로로 삼는다. create_all 이 켜져 있으면
            # ORM 정의만으로 테이블이 생겨 Alembic 이력과 어긋날 수 있으므로, 조용히 무시하지 않고
            # 기동을 거부한다(AUTO_CREATE_TABLES=false 를 명시하도록 강제).
            if self.auto_create_tables:
                raise ValueError(
                    "운영(env=prod)에서는 AUTO_CREATE_TABLES=false 로 두고 Alembic 을 스키마의 "
                    "유일한 소스로 삼아야 합니다."
                )
            # 사진 인식·임베딩은 키가 없으면 개발용 대체(고정 식단 스텁·해시 벡터)로
            # 내려간다. 운영에서 그대로 뜨면 사진과 무관한 음식이 끼니로 저장되고
            # 포인트까지 나가며, 의미 없는 벡터가 RAG 테이블에 섞인다(#2812).
            # 조용히 뜨는 대신 기동을 거부해 배포 단계에서 바로 드러나게 한다.
            problems = self.missing_ai_config()
            if problems:
                raise ValueError(
                    "운영(env=prod)에서는 사진 인식·임베딩 키가 필요합니다: " + "; ".join(problems)
                )
        return self

    def recognizer_problem(self) -> str | None:
        """설정된 식단 인식기를 실제로 쓸 수 없는 이유. 쓸 수 있으면 None. (#2812)"""
        engine = self.recognizer.strip().lower()
        if engine == "gemini":
            return None if self.gemini_api_key else "RECOGNIZER=gemini 인데 GEMINI_API_KEY 가 비어 있음"
        if engine == "claude":
            if self.litellm_base_url and self.litellm_api_key:
                return None
            return "RECOGNIZER=claude 인데 LITELLM_BASE_URL·LITELLM_API_KEY 가 비어 있음"
        if engine == "stub":
            return "RECOGNIZER=stub 은 개발용 고정 식단이라 운영에서 쓸 수 없음"
        return f"RECOGNIZER={engine} 는 운영에서 쓸 수 있는 인식기가 아님(gemini|claude)"

    def embedder_problem(self) -> str | None:
        """설정된 임베더를 실제로 쓸 수 없는 이유. 쓸 수 있으면 None. (#2812)"""
        chosen = self.embedder.strip().lower()
        if chosen == "gemini":
            return None if self.gemini_api_key else "EMBEDDER=gemini 인데 GEMINI_API_KEY 가 비어 있음"
        if chosen == "openai":
            return None if self.openai_api_key else "EMBEDDER=openai 인데 OPENAI_API_KEY 가 비어 있음"
        if chosen == "litellm":
            if self.litellm_base_url and self.litellm_api_key and self.litellm_embed_model:
                return None
            return "EMBEDDER=litellm 인데 LITELLM_BASE_URL·LITELLM_API_KEY·LITELLM_EMBED_MODEL 중 빈 값이 있음"
        if chosen == "hash":
            return "EMBEDDER=hash 는 개발용 해시 벡터라 운영에서 쓸 수 없음"
        return f"EMBEDDER={chosen} 는 알 수 없는 임베더"

    def missing_ai_config(self) -> list[str]:
        """운영 기동을 막는 AI 설정 문제 목록. 비어 있으면 통과."""
        return [p for p in (self.recognizer_problem(), self.embedder_problem()) if p]


def _comma_list(raw: str | None) -> list[str]:
    """콤마 구분 문자열 → 공백을 걷어 낸 비지 않은 항목 목록(순서 유지·중복 제거)."""
    items: list[str] = []
    for part in (raw or "").split(","):
        value = part.strip()
        if value and value not in items:
            items.append(value)
    return items


@lru_cache
def get_settings() -> Settings:
    return Settings()
