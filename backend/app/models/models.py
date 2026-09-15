"""
ORM 모델 — 프론트 계약(LocalApiInterceptor + drift 스키마)에 맞춤.

핵심 정렬 사항:
- 사용자 id 는 문자열(예: 'user-7d4e9a2c5f18')
- 식단은 나트륨(sodium_mg)·당류(sugar_g)를 1급 지표로 (고혈압·당뇨 특화)
- drift 테이블(diet_entries, exercise_sessions, schedule_events, notifications)과 1:1 대응

이번 STEP 1 에서는 테이블 생성만 검증하고, 살은 이후 STEP 에서 채웁니다.
"""

from __future__ import annotations

from datetime import datetime

from pgvector.sqlalchemy import Vector
from sqlalchemy import (
    Boolean,
    CheckConstraint,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    LargeBinary,
    String,
    Text,
    UniqueConstraint,
    false,
    func,
    text,
    true,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.config import get_settings
from app.db.session import Base

# 임베딩 차원은 설정값에서. 모델 교체 시 .env(EMBED_DIM)만 바꾸고 재임베딩.
EMBED_DIM = get_settings().embed_dim


class User(Base):
    __tablename__ = "users"

    # 계약상 문자열 id
    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    name: Mapped[str] = mapped_column(String(100), default="")
    hashed_password: Mapped[str] = mapped_column(String(255), default="")
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    # 관리자 권한(공공문서 업로드 등 민감 엔드포인트 접근). 기본 False.
    is_admin: Mapped[bool] = mapped_column(Boolean, default=False)
    # 계정 역할: 'member'(회원 앱) | 'trainer'(트레이너 앱). 두 앱은 완전히 분리된
    # 계정이지만 users 테이블은 공유하고 role 로 구분한다(트레이너↔회원 데이터 공유의 축).
    role: Mapped[str] = mapped_column(
        String(20), default="member", server_default="member", index=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )

    health_profile: Mapped["HealthProfile | None"] = relationship(
        back_populates="user", uselist=False, cascade="all, delete-orphan"
    )


class HealthProfile(Base):
    """건강 위험 정보 — /users/me/health 의 risk + 메타."""

    __tablename__ = "health_profiles"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), unique=True
    )

    risk_title: Mapped[str] = mapped_column(String(200), default="")
    risk_body: Mapped[str] = mapped_column(Text, default="")
    risk_level: Mapped[str] = mapped_column(
        String(20), default="low"
    )  # low|medium|high
    conditions: Mapped[str] = mapped_column(Text, default="")  # "고혈압, 당뇨 전단계"
    goals: Mapped[str] = mapped_column(Text, default="")

    # 개인정보(내 프로필 모달) + 온보딩 인구통계
    phone: Mapped[str] = mapped_column(String(20), default="")
    birth_date: Mapped[str] = mapped_column(String(10), default="")  # YYYY-MM-DD
    gender: Mapped[str] = mapped_column(String(10), default="")  # male|female|other
    height_cm: Mapped[float | None] = mapped_column(Float, nullable=True)
    weight_kg: Mapped[float | None] = mapped_column(Float, nullable=True)

    # 일일 영양 목표(식단 관리용)
    daily_calories: Mapped[int | None] = mapped_column(Integer, nullable=True)
    daily_sodium_mg: Mapped[int | None] = mapped_column(Integer, nullable=True)
    daily_sugar_g: Mapped[int | None] = mapped_column(Integer, nullable=True)
    daily_carbs_g: Mapped[int | None] = mapped_column(Integer, nullable=True)
    daily_protein_g: Mapped[int | None] = mapped_column(Integer, nullable=True)
    daily_fat_g: Mapped[int | None] = mapped_column(Integer, nullable=True)

    # 주간 운동 목표(운동 관리용)
    weekly_workout_goal: Mapped[int | None] = mapped_column(Integer, nullable=True)
    weekly_exercise_minutes_goal: Mapped[int | None] = mapped_column(
        Integer, nullable=True
    )
    weekly_burn_goal: Mapped[int | None] = mapped_column(Integer, nullable=True)

    # 운동 탭이 실제로 견주는 목표 (#1139) — 소모는 하루, 유형별은 한 주다.
    # 근력을 주 7 로 나누면 "2.3세트" 라는 뜻 없는 수가 되어, 유형별은 주간을
    # 원본으로 둔다.
    daily_burn_kcal: Mapped[int | None] = mapped_column(Integer, nullable=True)
    weekly_cardio_minutes: Mapped[int | None] = mapped_column(
        Integer, nullable=True
    )
    weekly_strength_sets: Mapped[int | None] = mapped_column(
        Integer, nullable=True
    )
    weekly_flexibility_minutes: Mapped[int | None] = mapped_column(
        Integer, nullable=True
    )

    # 온보딩 완료 여부(프론트 온보딩 게이팅용)
    onboarded: Mapped[bool] = mapped_column(Boolean, default=False)

    activity_points: Mapped[int] = mapped_column(Integer, default=0)
    activity_rank: Mapped[int | None] = mapped_column(Integer, nullable=True)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    user: Mapped["User"] = relationship(back_populates="health_profile")


class PointsLedger(Base):
    """활동 포인트 내역 — 적립(earn)·사용(spend)·회수(revoke)·반환(refund) 한 줄씩.
    (#1786, #1787)

    잔액은 [HealthProfile.activity_points] 가 들고, 이 표는 그 잔액이 무엇으로
    움직였는지를 남긴다. 둘은 같은 트랜잭션에서 함께 바뀐다(`points_service`).

    `kst_date` 는 이 줄이 생긴 KST 날짜다. 하루 적립 한도를 이 값으로 센다 —
    `created_at` 은 UTC 라 그대로 날짜를 뽑으면 아침 기록이 전날로 잡힌다.

    종류는 짝을 이룬다. 회수(revoke)는 같은 source 의 적립을, 반환(refund)은 같은
    source 의 사용을 되돌린다. 같은 기록(source)에 각 종류는 한 번씩이다 — 쿠폰
    교환은 `kind='spend'` 로 음수 `delta` 를, 담당 해제로 쿠폰이 취소되면
    `kind='refund'` 로 같은 크기의 양수 `delta` 를 남긴다(#1787).
    """

    __tablename__ = "points_ledger"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    kind: Mapped[str] = mapped_column(String(10))  # earn|spend|revoke|refund
    #: 잔액 변화량. 적립·반환은 양수, 사용·회수는 0 이하(실제로 뺀 값).
    delta: Mapped[int] = mapped_column(Integer)
    #: 규칙 이름 — diet_entry|exercise_manual|routine_complete|coupon_<item>.
    #: 적립 한도를 세는 단위다.
    reason: Mapped[str] = mapped_column(String(40))
    #: 근거 기록 종류와 id — diet_entry|exercise_session|points_coupon.
    source_type: Mapped[str | None] = mapped_column(String(40), nullable=True)
    source_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    kst_date: Mapped[str] = mapped_column(String(10))  # YYYY-MM-DD
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )

    __table_args__ = (
        CheckConstraint(
            "kind IN ('earn', 'spend', 'revoke', 'refund')",
            name="ck_points_ledger_kind",
        ),
        CheckConstraint(
            "(kind IN ('earn', 'refund') AND delta > 0) "
            "OR (kind IN ('spend', 'revoke') AND delta <= 0)",
            name="ck_points_ledger_delta_sign",
        ),
        UniqueConstraint(
            "user_id",
            "kind",
            "source_type",
            "source_id",
            name="uq_points_ledger_source",
        ),
        Index("ix_points_ledger_user_day", "user_id", "kst_date", "reason"),
    )


class PointsCoupon(Base):
    """포인트로 교환한 쿠폰 한 장. (#1787)

    교환하면 `issued` 로 생기고, 사용 처리되면 `used`, 기한이 지나면 `expired`,
    담당 트레이너 연결(PT 재등록)·헬스장 연결(개인 락커)이 끊겨 취소되면
    `cancelled` 다. 기한은 스케줄러 없이
    **읽는 쪽이 늦게 반영한다** — 조회·교환·사용 경로가 `expires_at` 이 지난
    `issued` 를 `expired` 로 내린다(`points_coupon_service._expire_stale`).

    - `cost` 는 교환할 때 쓴 포인트다. 연결 해제로 취소되면 이 값을 돌려준다 —
      카탈로그 가격이 나중에 바뀌어도 낸 만큼 돌려받는다.
    - `trainer_name`(PT 재등록)·`gym_name`(PT 재등록·개인 락커) 은 교환 시점의
      사본이다. 쿠폰 화면이 사용 뒤에도 어느 트레이너·헬스장에서 쓴 쿠폰인지 말할
      수 있게 한다.
    - 사용 처리는 늘 직원 확인 뒤 회원 휴대폰에서 한다. 누른 사람이 늘 이
      회원이라 따로 적지 않고, 시각만 `used_at` 에 남긴다.
    - 사용 가능한 쿠폰은 종류마다 회원당 한 장뿐이다(partial unique index).
    """

    __tablename__ = "points_coupons"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    #: 카탈로그 항목 id — pt_renewal|locker_month.
    item: Mapped[str] = mapped_column(String(40))
    cost: Mapped[int] = mapped_column(Integer)
    status: Mapped[str] = mapped_column(
        String(12), default="issued", server_default="issued"
    )  # issued|used|expired|cancelled
    trainer_id: Mapped[str | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    trainer_name: Mapped[str] = mapped_column(
        String(100), default="", server_default=""
    )
    gym_name: Mapped[str] = mapped_column(String(200), default="", server_default="")
    #: 교환 시도 단위 멱등키. 응답을 못 받고 다시 누른 교환이 두 장을 만들지 않는다.
    client_request_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    issued_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    #: 이 시각부터 쓸 수 없다(마지막 사용일 다음 날 KST 0시).
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    used_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    cancelled_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    #: 만료 3일 전 알림을 보낸 시각. 쿠폰마다 한 번만 보낸다.
    expiry_reminded_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    __table_args__ = (
        CheckConstraint(
            "status IN ('issued', 'used', 'expired', 'cancelled')",
            name="ck_points_coupons_status",
        ),
        CheckConstraint("cost > 0", name="ck_points_coupons_cost"),
        UniqueConstraint(
            "user_id", "client_request_id", name="uq_points_coupons_client_request"
        ),
        Index("ix_points_coupons_user_status", "user_id", "status"),
        # 종류마다 사용 가능한 쿠폰은 회원당 최대 한 장 — PT 재등록은 재등록 1회에
        # 1장, 개인 락커 쿠폰도 같은 규칙이다.
        Index(
            "uq_points_coupons_active_item",
            "user_id",
            "item",
            unique=True,
            postgresql_where=text("status = 'issued'"),
        ),
    )


class DietEntry(Base):
    """식단 기록 — drift DietEntries 대응. 나트륨·당류 포함."""

    __tablename__ = "diet_entries"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    date: Mapped[str] = mapped_column(String(10), index=True)  # YYYY-MM-DD
    meal_type: Mapped[str] = mapped_column(String(20))  # breakfast|lunch|dinner|snack
    time_label: Mapped[str] = mapped_column(String(10), default="")
    foods_json: Mapped[str] = mapped_column(Text, default="[]")  # [{name, calories}]
    total_calories: Mapped[int] = mapped_column(Integer, default=0)
    carbs_g: Mapped[float] = mapped_column(Float, default=0.0)
    protein_g: Mapped[float] = mapped_column(Float, default=0.0)
    fat_g: Mapped[float] = mapped_column(Float, default=0.0)
    sodium_mg: Mapped[int] = mapped_column(Integer, default=0)
    # 당류는 소수. 음식 단위(FoodNutrient.sugar_g)가 이미 Float 이라 항목 단위만
    # Integer 로 남아 있으면 6.3+8.5 같은 합이 절삭된다(프론트도 double 로 다룸).
    sugar_g: Mapped[float] = mapped_column(Float, default=0.0)
    engine: Mapped[str] = mapped_column(
        String(20), default=""
    )  # 인식 엔진(gemini|yolo)
    # 재시도 중복 저장 방지용 멱등키(클라 요청당 1회 생성). NULL 허용 → 기존/무키 요청은 제약 밖.
    idempotency_key: Mapped[str | None] = mapped_column(String(64), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )

    __table_args__ = (
        UniqueConstraint(
            "user_id", "idempotency_key", name="uq_diet_entries_user_idem"
        ),
    )


class DietPhoto(Base):
    """끼니 사진 — 회원이 올린 사진의 축소본. (#699)

    별도 테이블인 이유: `diet_entries` 는 하루 집계·트레이너 조회에서 통째로
    읽힌다. 바이트를 같은 행에 두면 사진이 필요 없는 모든 조회가 사진까지
    끌고 온다.

    저장 위치는 **공유 DB** 다. 오브젝트 스토리지는 버킷·자격증명·과금 주체가
    배포 환경(#414)에 매이는데, 사진 없이는 "회원이 올린 걸 트레이너가 본다"
    는 흐름 자체가 서지 않는다. 원본이 아니라 축소본만 두어(장변 상한 + JPEG
    재인코딩) 행 크기를 예측 가능하게 묶어 둔다 — 나중에 스토리지로 옮기더라도
    이 테이블이 이관 목록이 된다.
    """

    __tablename__ = "diet_photos"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    # 끼니 하나에 사진 하나. 재분석·재촬영은 이번 범위 밖이라 unique 로 못 박는다.
    entry_id: Mapped[str] = mapped_column(
        ForeignKey("diet_entries.id", ondelete="CASCADE"), unique=True
    )
    # 소유자를 사진에도 들고 있는다 — 접근 판정이 끼니 행을 거치지 않아도 되고,
    # 탈퇴 시 사진이 users 를 따라 함께 지워진다.
    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    content_type: Mapped[str] = mapped_column(String(40), default="image/jpeg")
    width: Mapped[int] = mapped_column(Integer, default=0)
    height: Mapped[int] = mapped_column(Integer, default=0)
    byte_size: Mapped[int] = mapped_column(Integer, default=0)
    data: Mapped[bytes] = mapped_column(LargeBinary)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class FoodNutrient(Base):
    """공공 식품영양성분 DB(식약처/국가표준) 큐레이션 테이블.

    Vision 인식이 준 '음식 이름'을 이 표에 매핑해 신뢰 가능한 1인분 영양가로 교체한다.
    (LLM 은 '무엇인지' 식별에 강하고, 정확한 영양 수치는 이 공공 DB 가 제공.)
    수치는 1회 제공량(serving_size_g) 기준. name_norm 은 매칭용 정규화 이름.
    """

    __tablename__ = "food_nutrients"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    name: Mapped[str] = mapped_column(String(100), index=True)
    name_norm: Mapped[str] = mapped_column(String(100), default="", index=True)
    category: Mapped[str] = mapped_column(
        String(30), default=""
    )  # 밥류|국·찌개류|구이류...
    serving_size_g: Mapped[float | None] = mapped_column(Float, nullable=True)
    calories: Mapped[float] = mapped_column(Float, default=0)  # kcal / 1인분
    sodium_mg: Mapped[float] = mapped_column(Float, default=0)  # mg  / 1인분
    sugar_g: Mapped[float] = mapped_column(Float, default=0)  # g   / 1인분
    carbs_g: Mapped[float | None] = mapped_column(Float, nullable=True)
    protein_g: Mapped[float | None] = mapped_column(Float, nullable=True)
    fat_g: Mapped[float | None] = mapped_column(Float, nullable=True)
    source: Mapped[str] = mapped_column(
        String(20), default="mfds"
    )  # 데이터 출처(식약처=mfds)


class ExerciseCatalogItem(Base):
    """운동 종목 참조표 — 이름을 소모 칼로리로 바꾸는 유일한 근거. (#1312)

    식단의 `food_nutrients` 와 같은 자리다. 인식(무엇을 했나)과 수치(얼마나
    소모하나)를 나눠, 수치는 이 표에서만 나오게 한다. 이름 해석이 AI 를 타든
    표 매칭으로 붙든 **숫자는 늘 여기서** 나오므로, 같은 기록을 다시 열어도 값이
    흔들리지 않는다 — 회원 앱·트레이너 앱·주간 합계가 같은 값을 본다(#1131).

    `met` 은 단위체중당 에너지 소비 계수(체중 1kg·1시간당 kcal)다. 화면에는
    꺼내지 않는다 — 집계 축은 칼로리 하나다(#1276).
    """

    __tablename__ = "exercise_catalog"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    #: 대표 종목 이름("러닝머신"). 화면에 "무엇으로 계산했는지" 보여 줄 때 쓴다.
    name: Mapped[str] = mapped_column(String(100), index=True)
    #: 매칭용 정규화 이름. `exercise_catalog.matcher.normalize` 의 결과다.
    name_norm: Mapped[str] = mapped_column(String(100), default="", index=True)
    #: 같은 종목의 다른 표기를 정규화해 `|` 로 이어 붙인 것("사이클|싸이클").
    #: 별칭 표를 따로 두지 않는 이유는 이 표가 시딩 후 읽기 전용이고 전체가
    #: 수백 행이라, 조인보다 전건 로드 한 번이 싸기 때문이다.
    aliases_norm: Mapped[str] = mapped_column(Text, default="", server_default="")
    #: 집계 유형 — cardio|strength|stretching|other. 이름이 매칭되면 회원이 고른
    #: 유형이 아니라 이 값이 맞다("줄넘기"를 근력으로 골라도 유산소다).
    type: Mapped[str] = mapped_column(String(20), default="other")
    met: Mapped[float] = mapped_column(Float, default=0)
    #: 데이터 출처. khpi=한국건강증진개발원 공공데이터, compendium=국제 표준표.
    source: Mapped[str] = mapped_column(String(20), default="khpi")


class ExerciseNameMatch(Base):
    """운동 이름 → 종목 해석 결과 캐시. (#1312)

    표 매칭으로 붙지 않는 자유 입력("런닝머신 30분", "PT 하체날")은 AI 가 종목으로
    접는다. 그 해석을 여기 적어 두는 이유는 둘이다.

    1. **값이 흔들리지 않게.** 같은 이름을 두 번 물으면 두 번 다른 답이 올 수
       있고, 그러면 주간 합계·트레이너 리포트·목표 달성률이 함께 흔들린다.
    2. **두 번 묻지 않게.** 호출 비용과 지연이 이름 하나당 한 번으로 끝난다.

    못 붙인 이름도 적는다(`catalog_id` 가 None). 안 그러면 해석되지 않는 이름을
    적을 때마다 계속 묻게 된다 — 실패는 성공보다 자주 일어난다.
    """

    __tablename__ = "exercise_name_matches"

    #: 정규화된 입력 이름이 곧 키다. 표기가 달라도 같은 이름이면 한 번만 묻는다.
    name_norm: Mapped[str] = mapped_column(String(100), primary_key=True)
    catalog_id: Mapped[int | None] = mapped_column(
        ForeignKey("exercise_catalog.id", ondelete="CASCADE"), nullable=True
    )
    #: 해석 확신도 0.0~1.0. 낮으면 채택하지 않고 유형 표로 폴백한다.
    confidence: Mapped[float] = mapped_column(Float, default=0)
    #: 누가 붙였나 — catalog=표 매칭, ai=이름 해석 모델.
    resolver: Mapped[str] = mapped_column(String(20), default="ai")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class ExerciseSession(Base):
    """운동 기록 — drift ExerciseSessions 대응."""

    __tablename__ = "exercise_sessions"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    week_start: Mapped[str] = mapped_column(String(10), index=True)  # 월요일 YYYY-MM-DD
    day_label: Mapped[str] = mapped_column(String(4))  # 월/화/...
    #: 운동 유형 — cardio|strength|flexibility|other 네 가지 (#996).
    #: 옛 값(walking·yoga·stretching)은 0053 마이그레이션에서 접었다.
    type: Mapped[str] = mapped_column(String(20))
    #: 회원이 적은 운동 이름("스쿼트", "러닝머신"). 유형은 집계 축이라 넷뿐이고,
    #: 실제로 무슨 운동을 했는지는 이 칸에만 남는다(#1276). 이 컬럼이 생기기 전
    #: 기록은 빈 문자열이다.
    name: Mapped[str] = mapped_column(String(100), default="", server_default="")
    minutes: Mapped[int] = mapped_column(Integer, default=0)
    #: 근력 기록의 세트 수. 근력은 시간이 아니라 세트로 읽는 운동이라 회원이
    #: 적은 수를 그대로 둔다(#1262). 다른 유형은 None 이고, 이 컬럼이 생기기
    #: 전의 근력 기록도 None 이다 — 그때는 분에서 환산해 읽는다.
    sets: Mapped[int | None] = mapped_column(Integer, nullable=True)
    #: 근력 기록의 한 세트당 횟수. 세트·중량과 한 벌이라 근력에만 있다(#1310).
    #: 12세트 60kg 만으로는 한 번에 몇 개를 들었는지가 남지 않아 같은 운동을
    #: 다시 짤 수 없다. 이 컬럼이 생기기 전 기록은 None 이다.
    reps: Mapped[int | None] = mapped_column(Integer, nullable=True)
    #: 근력 기록의 중량(kg, 소수점 한 자리). 세트와 짝이라 근력에만 있고, 다른
    #: 유형은 None 이다(#1276). 칼로리 계산에는 쓰지 않는다 — 같은 무게라도
    #: 사람마다 소모가 달라, 추정식에 넣으면 근거 없는 정밀도가 된다. 횟수도
    #: 같은 이유로 계산에 넣지 않는다.
    weight: Mapped[float | None] = mapped_column(Float, nullable=True)
    calories: Mapped[int] = mapped_column(Integer, default=0)
    #: 이 칼로리가 어디서 나왔나 — db=종목 참조표+체중, mixed=이름 해석은 AI 이고
    #: 수치는 참조표, estimate=유형 평균 어림값. 식단(`RecognizedFood.source`)과
    #: 같은 어휘다(#1312). 저장해 두는 이유는 참조표가 나중에 바뀌어도 그때 화면에
    #: 보여 준 근거는 그대로여야 하기 때문이다. 이 컬럼이 생기기 전 기록은 전부
    #: 어림값이라 기본값이 `estimate` 다.
    calorie_source: Mapped[str] = mapped_column(
        String(20), default="estimate", server_default="estimate"
    )
    # 운동 강도 — 칼로리 추정 배수의 근거이자 수정 시트 복원 값. light|moderate|high
    intensity: Mapped[str] = mapped_column(
        String(20), default="moderate", server_default="moderate"
    )
    #: 이 기록을 누가 만들었나. member=회원 수기, trainer_pt=PT 완료 파생,
    #: assigned_routine=배정 루틴 수행. 파생 기록은 일반 수기 기록처럼 회원이
    #: 고치거나 지울 수 없다(#499, #638).
    source: Mapped[str] = mapped_column(
        String(20), default="member", server_default="member"
    )
    # 배정 루틴 수행이면 원본 id와 당시 내용을 함께 보존한다. 루틴이 나중에
    # 수정·철회돼도 이미 끝낸 운동 기록은 당시 내용으로 남아야 한다(#638).
    assigned_routine_id: Mapped[str | None] = mapped_column(
        String(64), nullable=True, unique=True, index=True
    )
    assigned_trainer_id: Mapped[str | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )
    assigned_routine_name: Mapped[str] = mapped_column(
        String(100), default="", server_default=""
    )
    member_note: Mapped[str] = mapped_column(Text, default="", server_default="")
    trainer_feedback: Mapped[str] = mapped_column(Text, default="", server_default="")
    completed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class ScheduleEvent(Base):
    """일정 — drift ScheduleEvents 대응."""

    __tablename__ = "schedule_events"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    date: Mapped[str] = mapped_column(String(10), index=True)
    time: Mapped[str] = mapped_column(String(10), default="")
    title: Mapped[str] = mapped_column(String(200))
    category: Mapped[str] = mapped_column(
        String(20)
    )  # hospital|exercise|meal|medication|other
    emoji: Mapped[str] = mapped_column(String(10), default="")
    color_hex: Mapped[str] = mapped_column(String(10), default="#E0F2F7")


class Notification(Base):
    """알림 — drift NotificationItems 대응."""

    __tablename__ = "notifications"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    title: Mapped[str] = mapped_column(String(200))
    body: Mapped[str] = mapped_column(Text, default="")
    category: Mapped[str] = mapped_column(
        String(20)
    )  # reminder|health_check|achievement|system
    read: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class MemberNotificationSetting(Base):
    """회원 알림 수신 설정 — 기기가 아니라 계정 단위. (#489)

    전에는 사용자 앱이 SharedPreferences 에만 저장해 기기를 바꾸면 초기화됐고,
    무엇보다 **서버가 몰라서 알림을 만들 때 끌 수가 없었다.**

    컬럼 이름은 앱이 쓰던 키(`notif_*`)에서 접두사만 뗀 것이다. 새 이름을 만들면
    앱 화면과 대응이 흐려진다. 트레이너 쪽(`TrainerProfile.notify_*`)과 대칭이지만
    항목이 달라 테이블을 나눈다.

    행이 없으면 기본값(`notification_service.DEFAULTS`)이다 — 가입할 때마다 행을
    만들지 않아도 되고, 기본값을 바꾸면 한 번도 설정을 건드리지 않은 회원에게
    바로 적용된다.
    """
    __tablename__ = "member_notification_settings"

    member_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    diet_log: Mapped[bool] = mapped_column(
        Boolean, nullable=False, server_default=true(), default=True
    )
    exercise_reminder: Mapped[bool] = mapped_column(
        Boolean, nullable=False, server_default=true(), default=True
    )
    trainer_message: Mapped[bool] = mapped_column(
        Boolean, nullable=False, server_default=true(), default=True
    )
    ai_coaching: Mapped[bool] = mapped_column(
        Boolean, nullable=False, server_default=true(), default=True
    )
    #: 주간 리포트만 기본 꺼짐 — 앱의 현재 기본값과 같다.
    weekly_report: Mapped[bool] = mapped_column(
        Boolean, nullable=False, server_default=false(), default=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class CoachDocument(Base):
    """RAG 코치용 문서 + 임베딩 (STEP 7).

    두 종류의 문서가 공존:
      - 개인 문서(환자 데이터): user_id = 특정 사용자  → 그 사용자만 검색됨
      - 공공 문서(가이드라인 등): user_id = NULL        → 모든 사용자 공유

    검색 시 (user_id == 현재사용자 OR user_id IS NULL) 로 가져오면
    내 개인기록 + 공용 가이드라인만 나오고 남의 개인기록은 절대 안 섞인다.
    """

    __tablename__ = "coach_documents"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    # nullable: 공공 문서는 NULL(전체 공유), 개인 문서는 특정 user_id
    user_id: Mapped[str | None] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=True, index=True
    )
    # 'public' | 'meal' | 'workout' | 'profile' | 'vital' ...
    source: Mapped[str] = mapped_column(String(50), default="")
    # 도메인 필터용: 'diet' | 'exercise' | 'general' (도메인별 코치가 자기 자료만 검색)
    domain: Mapped[str] = mapped_column(String(20), default="general", index=True)
    #: 이 문서를 만든 원본 기록의 id (#603). 기록을 고치면 같은 참조의 문서를 지우고
    #: 다시 적재해, 옛 수치와 새 수치가 함께 검색되는 일이 없게 한다. 공공 문서와
    #: 참조를 남기기 전에 적재된 문서는 NULL 이다.
    source_ref: Mapped[str | None] = mapped_column(
        String(64), nullable=True
    )
    title: Mapped[str] = mapped_column(String(300), default="")
    content: Mapped[str] = mapped_column(Text)
    embedding: Mapped[list[float] | None] = mapped_column(
        Vector(EMBED_DIM), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class SocialAccount(Base):
    """소셜 로그인 연결 — 한 사용자에 여러 provider 를 붙일 수 있다.

    (provider, provider_user_id) 는 유일. 소셜 로그인 시 이 조합으로 사용자를 찾고,
    없으면 (이메일이 같은 기존 사용자에 연결하거나) 새 사용자를 만든다.
    """

    __tablename__ = "social_accounts"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    provider: Mapped[str] = mapped_column(
        String(20), index=True
    )  # kakao|google|naver|apple
    provider_user_id: Mapped[str] = mapped_column(String(128))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )

    __table_args__ = (
        UniqueConstraint("provider", "provider_user_id", name="uq_social_provider_uid"),
    )


class Place(Base):
    """온오프라인 연결: 장소 — /places/nearby. 카카오맵 연동 자리."""

    __tablename__ = "places"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    name: Mapped[str] = mapped_column(String(200))
    category: Mapped[str] = mapped_column(
        String(30)
    )  # medical|fitness|healthy_food|pharmacy
    address: Mapped[str] = mapped_column(String(300), default="")
    lat: Mapped[float | None] = mapped_column(Float, nullable=True)
    lng: Mapped[float | None] = mapped_column(Float, nullable=True)
    kakao_place_id: Mapped[str] = mapped_column(String(50), default="")


class GymProfile(Base):
    """헬스장 부가 정보 — `places`(category='fitness') 의 1:1 확장. (#324)

    헬스장 자체는 `Place` 다. 상담 검증(`consultation_service`)과 `/places/nearby`
    가 이미 `places` 를 쓰기 때문에 별도 테이블을 만들지 않았다. 다만 평점·영업시간
    같은 헬스장 전용 값을 `places` 에 넣으면 병원·약국·건강식이 공유하는 테이블이
    오염되므로 여기로 분리한다(`TrainerProfile` 이 `User` 를 확장하는 것과 같은 꼴).
    """

    __tablename__ = "gym_profiles"

    place_id: Mapped[str] = mapped_column(
        String(64), ForeignKey("places.id", ondelete="CASCADE"), primary_key=True
    )
    #: 카카오 Local 은 평점을 주지 않는다 — 발견된 헬스장은 None.
    rating: Mapped[float | None] = mapped_column(Float, nullable=True)
    weekday_hours: Mapped[str] = mapped_column(String(50), default="")
    weekend_hours: Mapped[str] = mapped_column(String(50), default="")
    phone: Mapped[str] = mapped_column(String(20), default="")
    tags_json: Mapped[str] = mapped_column(
        Text, default="[]"
    )  # ["다이어트", "재활운동"]
    #: 제휴 헬스장 **표시** 값 — `GymOut` 으로 내려가고 `GET /gyms?partner_only=true`
    #: 로 목록을 좁히는 데 쓴다. **접근 제어가 아니다.**
    #:
    #: 상담 대상 검증(`consultation_service._validate_target`)과 트레이너 노출 경로
    #: (`/trainers`, `/trainers/recommended`, `/gyms/{id}/trainers`)는 이 값을 보지
    #: 않는다 — 소속 장소가 `category='fitness'` 인 활성 트레이너인지로 판단한다.
    #: 예전 주석은 "제휴 헬스장만 트레이너 연결·상담이 가능하다"고 적어 두었으나 그
    #: 규칙을 강제하는 코드는 없었다. 제휴를 실제 조건으로 삼으려면 위 경로들을 함께
    #: 고쳐야 한다. (#1626)
    is_partner: Mapped[bool] = mapped_column(
        Boolean, nullable=False, server_default=false(), default=False, index=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class MemberGym(Base):
    """회원↔헬스장 링크 — 회원의 '내 헬스장'. (#444)

    전에는 이 링크가 없어서 담당 트레이너의 소속(`TrainerProfile.gym_id`)에서
    파생시켰다. 그래서 트레이너만 해제해도 헬스장이 함께 사라졌다 — 앱 MY 탭은
    두 해제를 따로 제공하는데 서버가 그 구분을 표현하지 못했다.

    `TrainerClient` 와 달리 `active` 이력 컬럼이 없다. 담당 링크는 루틴·채팅·일정이
    참조해 지우면 이력이 끊기지만, 헬스장 링크를 참조하는 것은 없어 해제 시 행을
    지우면 된다. 회원당 1곳이라는 불변식은 `member_id` 를 PK 로 두어 구조로 강제한다
    (partial unique index 가 필요 없다).
    """

    __tablename__ = "member_gyms"

    member_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    #: 헬스장은 `places`(category='fitness'). 장소가 사라지면 링크도 사라진다 —
    #: gym_id 는 NOT NULL 이라 SET NULL 을 쓸 수 없고, 없어진 헬스장을 '내 헬스장'
    #: 으로 남겨 둘 이유도 없다.
    gym_id: Mapped[str] = mapped_column(
        ForeignKey("places.id", ondelete="CASCADE"), index=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class ConsultationRequest(Base):
    """회원이 트레이너 한 사람에게 보내는 상담 요청.

    헬스장 전체를 대상으로 하는 갈래(`target_type='gym'`)는 폐지됐고, 그때 만들어진
    이력도 남아 있지 않아 `gym_id` 컬럼까지 걷어냈다(#726). `target_type` 은 값이
    하나뿐이지만 아래 부분 유니크 인덱스의 조건이 참조하므로 남긴다.
    """

    __tablename__ = "consultation_requests"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    member_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    target_type: Mapped[str] = mapped_column(String(20))
    trainer_id: Mapped[str | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    exercise_goal: Mapped[str] = mapped_column(String(30))
    health_purpose_type: Mapped[str] = mapped_column(String(30))
    health_purpose_detail: Mapped[str | None] = mapped_column(Text, nullable=True)
    preferred_date: Mapped[str] = mapped_column(String(10))
    preferred_time_slot: Mapped[str] = mapped_column(String(20))
    #: 회원이 데이터 공유에 동의한 시각. 트레이너가 수락해 담당이 생기면 이
    #: 값이 담당 링크로 옮겨 간다 — 회원은 신청할 때 동의하고, 연결은 나중에
    #: 트레이너가 만든다. (#1022)
    data_consent_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    message: Mapped[str | None] = mapped_column(Text, nullable=True)
    status: Mapped[str] = mapped_column(
        String(20), default="pending", server_default="pending"
    )
    #: 처리한 트레이너. 지금은 요청 대상(trainer_id)과 항상 같지만, 인박스 이력이
    #: "누가 언제 처리했는지"를 그대로 보여 줘야 해 따로 남긴다. (#467)
    decided_by: Mapped[str | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    #: 승인·거절 시각. updated_at 은 어떤 수정으로도 갱신되어 근거가 못 된다.
    decided_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    #: 거절 사유. 승인 시에는 비어 있다.
    decision_note: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    __table_args__ = (
        Index(
            "uq_consultation_requests_pending_trainer",
            "member_id",
            "trainer_id",
            unique=True,
            postgresql_where=text("target_type = 'trainer' AND status = 'pending'"),
        ),
        Index(
            "ix_consultation_requests_member_created_at",
            "member_id",
            "created_at",
        ),
        # 트레이너 인박스 — 나를 지정한 요청만 읽는다. (#467)
        Index("ix_consultation_requests_trainer_status", "trainer_id", "status"),
    )


#
# ---------------------------------------------------------------------------
# 트레이너 도메인 — 트레이너↔회원 데이터 공유의 뼈대.
#
# 핵심 설계(진짜 공유): "고객"은 별도 복제 테이블이 아니라 실제 회원 User 다.
# TrainerClient 링크로 트레이너와 회원을 잇고, 트레이너가 보는 고객 식단/운동은
# 회원이 회원 앱에서 직접 남긴 그 레코드(DietEntry/ExerciseSession)를 읽는다.
# 아래 테이블은 "공유되는 상호작용"(루틴 배정·완료기록·채팅·스케줄)만
# 담는다. 응답 형태는 트레이너 프론트 drift 계약(TrainerClients/ClientAiRoutines/
# ClientRoutineHistory/ClientChatMessages/TrainerScheduleEntries)에 정렬한다.
# ---------------------------------------------------------------------------


class TrainerProfile(Base):
    """트레이너 전용 프로필 — 프론트 seedTrainerProfile / Figma MY 화면 대응.

    회원의 HealthProfile 과 별개(역할이 다른 계정). 이름/이메일은 User 에 있고,
    여기엔 전문분야·경력·자격증·소속 헬스장 정보만 둔다.
    """

    __tablename__ = "trainer_profiles"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    trainer_id: Mapped[str] = mapped_column(
        # unique=True 가 이미 유니크 인덱스를 만들므로 index=True 는 잉여(중복 인덱스). 제거.
        ForeignKey("users.id", ondelete="CASCADE"),
        unique=True,
    )
    phone: Mapped[str] = mapped_column(String(20), default="")
    specialty: Mapped[str] = mapped_column(String(50), default="")  # 퍼스널 트레이너
    career_years: Mapped[int] = mapped_column(Integer, default=0)  # 7 → "7년"
    intro: Mapped[str] = mapped_column(Text, default="")
    certifications_json: Mapped[str] = mapped_column(
        Text, default="[]"
    )  # ["생활스포츠지도사 2급", ...]
    #: 소속 헬스장(`places.id`). 아래 gym_* 문자열 컬럼을 대신한다 — 문자열만으로는
    #: 한 헬스장에 여러 트레이너를 묶을 수 없었다(#324, #301). 트레이너 앱이 아직
    #: gym_* 를 읽으므로 두 표현이 당분간 공존하고, 값이 있으면 gym_id 가 우선이다.
    gym_id: Mapped[str | None] = mapped_column(
        String(64),
        ForeignKey("places.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    #: 추천 레일에 올릴 한 줄 사유. 빈 문자열이면 추천 대상이 아니다.
    recommend_reason: Mapped[str] = mapped_column(
        String(200), nullable=False, server_default="", default=""
    )
    gym_name: Mapped[str] = mapped_column(String(100), default="")
    gym_address: Mapped[str] = mapped_column(String(300), default="")
    gym_hours: Mapped[str] = mapped_column(String(50), default="")
    gym_phone: Mapped[str] = mapped_column(String(20), default="")
    # 알림 수신 설정(#379). 기기 로컬이 아니라 계정 단위 — 트레이너는 센터 PC 와
    # 태블릿을 오간다. 기본값은 서버가 정한다(모두 켬 / 30분 전).
    notify_new_message: Mapped[bool] = mapped_column(
        Boolean, nullable=False, server_default=true(), default=True
    )
    notify_session_reminder: Mapped[bool] = mapped_column(
        Boolean, nullable=False, server_default=true(), default=True
    )
    reminder_lead_minutes: Mapped[int] = mapped_column(
        Integer, nullable=False, server_default="30", default=30
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class TrainerInviteCode(Base):
    """헬스장이 발급하는 트레이너 가입 초대 코드. (#475)

    트레이너 계정은 시드 스크립트로만 만들 수 있었다 — `/auth/register` 는 회원
    전용이라 트레이너 앱에서 가입해도 member 계정이 생겨 `/trainer/me` 가 403 을
    돌려줬다. 그래서 트레이너 앱의 가입 진입점이 데모에서만 열려 있었다.

    코드가 **소속을 결정한다**는 점이 핵심이다. 상담 대상 트레이너에게는 소속
    헬스장이 요구되므로(#443·#451), 소속을 가입 시점에 확정하면 "가입은 됐는데
    아무것도 못 하는" 상태가 생기지 않는다. 아무나 트레이너로 가입해 회원 상담을
    받는 것도 구조로 막힌다.

    한 번 쓰면 끝이다(`used_by`). 여러 명을 받으려면 헬스장이 코드를 여러 개
    발급한다 — 사용 횟수를 세는 것보다 "누가 이 코드를 썼는지"가 남는 편이
    나중에 추적할 수 있다.
    """

    __tablename__ = "trainer_invite_codes"

    #: 사람이 옮겨 적는 값이라 코드 자체가 PK 다. 대문자·숫자만 쓰고 대소문자
    #: 구분 없이 조회한다(입력 실수를 코드 오류로 만들지 않는다).
    code: Mapped[str] = mapped_column(String(32), primary_key=True)
    gym_id: Mapped[str] = mapped_column(
        ForeignKey("places.id", ondelete="CASCADE"), index=True
    )
    #: 만료 시각. NULL 이면 만료 없음.
    expires_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    #: 이 코드로 가입한 트레이너. NULL 이면 아직 쓰이지 않았다.
    used_by: Mapped[str | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    used_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class TrainerClient(Base):
    """트레이너↔회원 담당 링크. 트레이너의 '고객 목록'은 이 링크로 정의된다.

    goal 은 트레이너가 설정한 코칭 목표(예: '혈압 관리 · 체중 감량'). 한 회원이 한
    트레이너에게 중복 배정되지 않도록 (trainer, member) 유일. 또한 회원측 API 는
    '현재 담당 코치 1명'을 전제하므로, 회원당 active 링크는 최대 1개로 partial
    unique index 로 강제한다(복수 트레이너 동시 배정 방지).

    **`active` 와 `dormant` 는 다른 축이다.** (#707)

    * `active` — 담당 관계 자체가 살아 있는가. 해제(헬스장 탈퇴·다른 트레이너
      배정·탈퇴)만 이 값을 내리고, 내려가면 회원측은 '담당 없음'이 되며 예약·
      코치 조회가 막힌다. 트레이너가 화면에서 건드리는 값이 아니다.
    * `dormant` — 트레이너가 이 회원을 지금 적극적으로 관리하고 있는가. 화면의
      '활성/휴면' 배지가 이 값이다. 휴면으로 내려도 담당 관계·기록·채팅은 그대로
      남는다.

    둘을 한 컬럼으로 겸하면 트레이너가 '휴면'을 누르는 순간 담당 관계가 끊겨
    회원 앱에서 코치가 사라진다 — 그래서 나눈다.
    """

    __tablename__ = "trainer_clients"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    trainer_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    member_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    goal: Mapped[str] = mapped_column(String(200), default="")
    #: 담당 관계가 살아 있는가(해제 여부). 트레이너 화면의 배지가 아니다.
    active: Mapped[bool] = mapped_column(Boolean, default=True)
    #: 회원이 식단·운동·신체 정보 공유에 동의한 시각. (#1022)
    #:
    #: 트레이너는 담당이 되는 순간 회원의 건강 기록을 읽는다. 그 동의를 언제
    #: 받았는지 답할 수 있어야 하므로 링크에 함께 남긴다. 비어 있는 링크는 이
    #: 기능 이전에 만들어진 것이다.
    data_consent_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    #: 트레이너의 관리 상태 — True 면 화면에 '휴면'으로 보인다.
    dormant: Mapped[bool] = mapped_column(Boolean, default=False)
    sort_order: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )

    __table_args__ = (
        UniqueConstraint("trainer_id", "member_id", name="uq_trainer_client"),
        # 회원당 active 담당은 최대 1명(휴면 링크는 과거 이력으로 여러 개 허용).
        Index(
            "uq_trainer_client_active_member",
            "member_id",
            unique=True,
            postgresql_where=text("active"),
        ),
    )


class TrainerClientInvite(Base):
    """트레이너가 회원에게 보내는 담당 요청. 수락하면 [TrainerClient] 가 생긴다.

    상담 요청(`consultation_requests`)의 **반대 방향**이다. 한 표에 방향 컬럼을
    더해 겸하지 않는 이유는 회원이 채우는 값(운동 목표·건강 목적·희망 일시)이
    트레이너가 보내는 요청에는 존재하지 않기 때문이다. 한 표에 두면 그 컬럼들이
    한쪽 방향에서만 채워지는 반쪽 행이 되고, 두 인박스가 같은 제약을 공유하게
    된다. (#919)

    **담당 관계는 회원이 수락해야 생긴다.** 트레이너가 명단에 곧바로 밀어 넣지
    않는 것은 담당이 상대의 식단·건강 기록을 여는 권한이라서다 — 한쪽이
    일방적으로 만들 수 있으면 그 권한이 동의 없이 열린다.

    (trainer, member) 부분 유니크(대기 중일 때만) — 같은 회원에게 대기 중인
    요청이 둘일 수 없다. 거절당한 뒤 다시 보내는 것은 허용한다.
    """

    __tablename__ = "trainer_client_invites"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    trainer_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    member_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    #: 트레이너가 회원에게 함께 보내는 한마디. 회원이 누구의 요청인지 알아볼
    #: 근거라, 비어 있어도 화면은 트레이너 이름·소속으로 채운다.
    message: Mapped[str | None] = mapped_column(Text, nullable=True)
    status: Mapped[str] = mapped_column(
        String(20), default="pending", server_default="pending"
    )
    #: 회원이 결정한 시각. 트레이너가 거둬들이면(cancelled) 그 시각도 여기 남는다.
    decided_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )

    __table_args__ = (
        Index(
            "uq_trainer_client_invite_pending",
            "trainer_id",
            "member_id",
            unique=True,
            postgresql_where=text("status = 'pending'"),
        ),
        # 회원 앱이 읽는 질의 그대로 — 나에게 온 대기 중인 요청.
        Index(
            "ix_trainer_client_invites_member_status", "member_id", "status"
        ),
    )


class MemberPairingCode(Base):
    """회원이 트레이너에게 불러 주는 6자리 일회용 동기화 코드. (#1634)

    예전에는 회원 앱 MY 탭이 `User.id`(`user-<12자리 hex>`)를 "내 회원 ID"로
    보여 주고 트레이너가 그것을 완전 일치로 입력했다. 마주 앉아 불러 주기에는
    12자리 hex 가 옮겨 적을 수 있는 형태가 아니었다.

    **코드를 발급하는 행위가 곧 데이터 공유 동의다** (#1022). 담당 관계는 상대의
    식단·건강 기록을 여는 권한이라 동의 없이 열 수 없는데, 회원이 코드를 띄운
    화면이 공유 범위를 말하고 그 코드를 직접 불러 준다. 그래서 [created_at] 이
    동의 시각이 되고, 트레이너가 코드를 쓰는 순간 담당이 바로 성립한다.

    **회원당 한 행이다.** 코드가 여러 개 살아 있으면 회원이 자기가 무엇을 줬는지
    모른다. 시트를 다시 열어도 유효한 코드는 그대로 나와야, 트레이너가 이미
    받아 적은 값이 말없이 무효가 되지 않는다.

    쓰면 행을 지운다 — 1회용이다. 만료된 행은 다음 발급·사용 때 정리한다.
    """

    __tablename__ = "member_pairing_codes"

    member_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    #: 사람이 불러 주고 받아 적는 값이라 숫자 6자리다. 만료된 뒤에도 행이 남아
    #: 있는 동안은 같은 코드가 두 번 발급되지 않도록 유일하게 둔다.
    code: Mapped[str] = mapped_column(String(6), unique=True, index=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    #: 발급 시각 = 데이터 공유 동의 시각. 담당 링크의 `data_consent_at` 이 된다.
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class TrainerClientMemo(Base):
    """트레이너가 담당 회원에 대해 남긴 메모. 회원에게는 보이지 않는다.

    출처가 둘이다 — 트레이너가 회원 상세에서 직접 쓴 메모(source='trainer')와,
    채팅에서 감지한 신호를 저장한 메모(source='chat_insight'). 둘을 한 테이블에
    두는 이유는 회원 상세가 **하나의 목록**으로 보여 주기 때문이다.

    `insight_id` 는 채팅 인사이트의 식별자다. 같은 인사이트를 여러 번 저장해도
    메모가 늘지 않도록 (trainer, member, insight_id) 를 유일로 둔다 — 직접 쓴
    메모는 이 값이 NULL 이라 제약에 걸리지 않는다(Postgres 는 NULL 을 서로 다른
    값으로 본다).
    """

    __tablename__ = "trainer_client_memos"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    trainer_id: Mapped[str] = mapped_column(
        # 단독 인덱스를 두지 않는다 — 아래 (trainer_id, member_id) 복합 인덱스가
        # 선행 컬럼으로 커버한다. 쓰기마다 갱신 비용만 늘 뿐이다.
        ForeignKey("users.id", ondelete="CASCADE")
    )
    member_id: Mapped[str] = mapped_column(
        # 회원 삭제 CASCADE 가 이 컬럼으로 행을 찾으므로 단독 인덱스가 필요하다
        # (복합 인덱스의 선행 컬럼이 아니라 커버되지 않는다).
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    body: Mapped[str] = mapped_column(Text, default="")
    #: 'trainer' | 'chat_insight'
    source: Mapped[str] = mapped_column(String(16), default="trainer")
    insight_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    #: 채팅 인사이트 종류(discomfort|negativeFeedback). 직접 쓴 메모는 빈 문자열.
    insight_kind: Mapped[str] = mapped_column(String(32), default="")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        # 다른 경로(예: 일괄 수정)가 본문을 고쳐도 시각이 따라오도록 onupdate 를
        # 건다 — TrainerProfile.updated_at 과 같은 규약.
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    __table_args__ = (
        UniqueConstraint(
            "trainer_id", "member_id", "insight_id", name="uq_trainer_client_memo_insight"
        ),
        # 응답 스키마(TrainerMemoOut.source)가 두 값만 받으므로, 다른 값이 한 행이라도
        # 들어가면 그 회원의 메모 **목록 전체**가 검증 실패로 500 이 된다. 입력은
        # 이미 Literal 로 막지만 DB 에서도 못 박는다.
        CheckConstraint(
            "source IN ('trainer', 'chat_insight')",
            name="ck_trainer_client_memo_source",
        ),
        Index("ix_trainer_client_memos_pair", "trainer_id", "member_id"),
    )


class TrainerRoutine(Base):
    """트레이너/AI가 회원에게 배정한 루틴 — 프론트 ClientAiRoutines 대응.

    source: 'ai'(AI 추천) | 'trainer'(트레이너 직접 배정). 회원 앱에서 '받은 루틴'
    으로도 읽힌다(양쪽에서 보이는 공유 데이터).

    **다중 세션 프로그램은 세션당 한 행이다.** (#709) 트레이너가 세션 여러 개로
    구성한 프로그램을 배정하면 각 세션이 루틴 하나가 되고, `program_name` 으로
    묶이며 `session_order` 가 순서를 지킨다. 세션이 하나뿐인 프로그램은 예전과
    똑같이 행 하나이고 `session_name` 이 비어 있다 — 회원 화면에 없던 세션
    라벨이 갑자기 생기지 않게 하려는 것이다.

    `exercises_json` 은 그 세션의 운동 구성을 그대로 담는다. 예전에는 운동
    이름들을 `reason` 에 이어 붙이는 것이 전부라 세트·횟수·중량이 회원에게
    닿지 않았다.
    """

    __tablename__ = "trainer_routines"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    #: 배정한 트레이너. 담당 트레이너가 없는 회원에게 AI 가 안전 범위에서 직접
    #: 추천한 개인운동은 이 값이 비어 있다(#782) — 승인할 사람이 없기 때문이다.
    trainer_id: Mapped[str | None] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True, nullable=True
    )
    member_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    name: Mapped[str] = mapped_column(String(100))
    minutes: Mapped[int] = mapped_column(Integer, default=0)
    #: 운동 유형 — 유산소|근력|스트레칭|기타 네 가지 (#996).
    type: Mapped[str] = mapped_column(String(20))
    #: 이 루틴을 언제 하기로 했나. 트레이너가 달력에서 고른 날이고, 비어 있으면
    #: "날짜를 정하지 않음"이다 — 이 칸이 생기기 전 배정이 그렇다. (#1276)
    exercise_date: Mapped[str | None] = mapped_column(String(10), nullable=True)
    #: 트레이너가 정한 강도. 예상 칼로리와 회원이 완료할 때의 기본값이 된다.
    #: 예전에는 배정에 강도를 실을 자리가 없어 늘 'moderate' 로 계산했다. (#1276)
    intensity: Mapped[str] = mapped_column(
        String(20), default="moderate", server_default="moderate"
    )
    #: 근력 루틴의 세트 수·횟수·중량(kg). 다른 유형은 비어 있다. (#1276, #1310)
    sets: Mapped[int | None] = mapped_column(Integer, nullable=True)
    reps: Mapped[int | None] = mapped_column(Integer, nullable=True)
    weight: Mapped[float | None] = mapped_column(Float, nullable=True)
    reason: Mapped[str] = mapped_column(String(200), default="")
    source: Mapped[str] = mapped_column(String(20), default="ai")  # ai|trainer
    #: 검토 상태 — approved(회원에게 노출) | pending(트레이너 검토 대기) |
    #: dismissed(추천하지 않기로 함).
    #:
    #: 기본이 approved 인 것이 하위 호환의 핵심이다. 지금까지의 배정은 모두
    #: 트레이너가 보낸 것이므로 그대로 회원에게 보여야 한다. AI 가 만든 후보만
    #: pending 으로 들어와 승인 전까지 회원 조회에서 빠진다.
    status: Mapped[str] = mapped_column(String(20), default="approved", index=True)
    #: 트레이너가 승인/거절한 시각. pending 인 동안은 비어 있다.
    reviewed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    #: 검토한 트레이너 id. 배정 트레이너와 같지만, 나중에 대리 검토가 생겨도
    #: 누가 판단했는지는 남아야 한다.
    reviewed_by: Mapped[str | None] = mapped_column(String(64), nullable=True)
    #: 여러 세션을 한 프로그램으로 묶는 이름. 단일 루틴 배정은 빈 문자열이다.
    program_name: Mapped[str] = mapped_column(String(100), default="")
    #: 이 루틴이 어느 세션인가. 세션이 하나뿐이면 비어 있다.
    session_name: Mapped[str] = mapped_column(String(100), default="")
    #: 프로그램 안에서의 세션 순서(0부터). 단일 루틴은 0.
    session_order: Mapped[int] = mapped_column(Integer, default=0)
    #: 그 세션의 운동 구성. 초안의 운동 항목과 같은 형식이다.
    exercises_json: Mapped[str] = mapped_column(Text, default="[]")
    #: 이 제안이 무엇을 보고 만들어졌나 — 짧은 근거 문구 목록(#790).
    #: `["최근 PT 피드백 반영", "혈압 관리 목표"]` 처럼 트레이너가 승인 판단에
    #: 쓰는 재료다. `reason` 과 나눠 둔 이유는 그쪽이 **회원에게 전달되는
    #: 문구**라는 것이다 — 한 필드에 담으면 내부 판단이 회원 화면에 함께 나간다.
    evidence_json: Mapped[str] = mapped_column(
        Text, default="[]", server_default="[]"
    )
    sort_order: Mapped[int] = mapped_column(Integer, default=0)
    # 재전송 중복 배정 방지용 멱등키(전송 시도당 1회 생성). NULL 허용 → 기존/무키
    # 요청은 제약 밖. DietEntry.idempotency_key 와 같은 방식이다.
    client_request_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )

    __table_args__ = (
        UniqueConstraint(
            "trainer_id",
            "member_id",
            "client_request_id",
            name="uq_trainer_routines_client_request",
        ),
    )


class TrainerProgramDraft(Base):
    """트레이너가 저장해 둔 프로그램 초안. 회원에게 배정되기 전의 작업물이다. (#708)

    회원과 묶이지 않는다 — 초안은 "이 트레이너가 만들어 둔 구성"이고, 회원 배정은
    저장한 초안을 불러와 기존 배정 경로로 보내는 별개의 행동이다. 그래서
    `member_id` 가 없다.

    `sessions_json` 은 편집기의 세션 목록을 순서 그대로 담는다
    (`[{id,name,exercises:[{id,name,sets,reps,weight,duration,distance,rest,
    rpe,memo,type,source}]}]`). 세션 순서가 곧 배열 순서다 — 별도 정렬 컬럼을
    두면 배열과 어긋날 수 있고, 편집기는 이미 순서를 가진 목록을 들고 있다.

    운동의 세트·횟수·중량은 전부 자유 문자열("10회", "60")이라 숫자로 정규화하면
    트레이너가 적어 둔 표현이 사라진다 — 저장·복원에서 값이 손실되지 않는 것이
    이 기능의 요구다. 스케줄의 `program_json` 과 같은 방식이되 한 겹 더 깊다.

    #708 은 세션 하나만 담았고(`session_name`/`exercises_json`), #709 에서 세션
    배열로 올렸다. `0039_program_sessions` 가 기존 행을 세션 1개짜리 배열로
    옮긴다.
    """

    __tablename__ = "trainer_program_drafts"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    trainer_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    name: Mapped[str] = mapped_column(String(100), default="")
    goal: Mapped[str] = mapped_column(String(200), default="")
    period: Mapped[str] = mapped_column(String(100), default="")
    memo: Mapped[str] = mapped_column(Text, default="")
    sessions_json: Mapped[str] = mapped_column(Text, default="[]")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class TrainerProgramTemplate(Base):
    """트레이너가 반복해 쓰는 운동 블록. (#920)

    초안(`trainer_program_drafts`)과 답하는 질문이 다르다 — 초안은 "이 회원에게
    짜 둔 프로그램", 템플릿은 "어느 회원에게든 끼워 넣는 블록"이다. 그래서 세션
    개념이 없고 운동 목록 하나만 갖는다. 적용하면 AI 제안 **위에 덧붙는다.**

    지금까지 이 목록은 앱 소스의 `const` 였다. 트레이너마다 다른 것이 템플릿의
    존재 이유인데 모두가 같은 셋을 봤고, 내용도 한국어로 고정돼 영어 화면에
    그대로 남았다.

    `exercises_json` 은 `[{name, minutes, type}]` 을 순서 그대로 담는다. 배열
    순서가 곧 표시 순서다 — 별도 정렬 컬럼은 배열과 어긋날 여지만 만든다
    (`trainer_program_drafts.sessions_json` 과 같은 규약).
    """

    __tablename__ = "trainer_program_templates"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    trainer_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    name: Mapped[str] = mapped_column(String(100), default="")
    goal: Mapped[str] = mapped_column(String(200), default="")
    exercises_json: Mapped[str] = mapped_column(Text, default="[]")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class TrainerReportFeedback(Base):
    """주간 리포트에 트레이너가 **작성 중인** 피드백 초안. (#821)

    회원에게 나간 문구가 아니다 — 전송된 리포트는 채팅 스레드에 `ChatMessage`
    로 남는다. 여기 있는 값은 트레이너가 다음에 이어서 쓸 자리를 잡아 주는
    작업물이라, 전송해도 지우지 않는다. 전송 이력과 작성 중인 초안은 서로
    다른 질문에 답한다("무엇을 보냈나" / "무엇을 쓰다 말았나").

    (trainer, member, week_start) 하나당 한 행이다. 주차를 키에 넣어야 지난
    주 리포트를 다시 열었을 때 그때 쓰던 문구가 그대로 나온다 — 고객당 하나만
    두면 주를 옮기는 순간 남의 주 문구가 따라온다.

    `week_start` 는 그 주 월요일 `YYYY-MM-DD`. `ExerciseSession.week_start` 와
    같은 방식이라 주차 정규화 규칙(`week_start_of`)을 그대로 쓴다.
    """

    __tablename__ = "trainer_report_feedback"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    trainer_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    member_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    week_start: Mapped[str] = mapped_column(String(10), index=True)  # 월요일 YYYY-MM-DD
    body: Mapped[str] = mapped_column(Text, default="")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    __table_args__ = (
        UniqueConstraint(
            "trainer_id",
            "member_id",
            "week_start",
            name="uq_trainer_report_feedback_week",
        ),
    )


class TrainerDailyTaskProgress(Base):
    """대시보드 `오늘 할 일` 의 하루 진행 상태. (#1633)

    기기 로컬이 아니라 **계정 단위** — 트레이너는 센터 PC 와 태블릿을 오간다(알림
    수신 설정과 같은 이유). 체크는 "트레이너 자신의 확인 표시"지만, 그 표시가
    기기마다 다르면 한쪽에서 끝낸 일이 다른 쪽에서 다시 할 일로 보인다.

    (trainer_id, date) 하나당 한 행이고, 앱이 그날 목록을 바꿀 때마다 통째로
    덮어쓴다. `pending_keys` 는 다음 날의 `지난 할 일` 판정이, `dismissed_keys` 는
    같은 날 다시 연 화면이 읽는다. 키는 앱이 만드는 미션 키(`report-<id>` 등)라
    서버는 내용을 해석하지 않는다.

    `date` 는 KST `YYYY-MM-DD` — `TrainerSchedule.date` 와 같은 표기라 문자열
    비교로 보관 기간을 자른다.
    """

    __tablename__ = "trainer_daily_task_progress"

    trainer_id: Mapped[str] = mapped_column(
        String(64), ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    date: Mapped[str] = mapped_column(String(10), primary_key=True)
    total: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0", default=0)
    completed_today: Mapped[int] = mapped_column(
        Integer, nullable=False, server_default="0", default=0
    )
    completed_carried_over: Mapped[int] = mapped_column(
        Integer, nullable=False, server_default="0", default=0
    )
    pending_keys_json: Mapped[str] = mapped_column(
        Text, nullable=False, server_default="[]", default="[]"
    )
    dismissed_keys_json: Mapped[str] = mapped_column(
        Text, nullable=False, server_default="[]", default="[]"
    )
    #: 체크한 키. `pending_keys` 에서 거꾸로 추정하면 마지막 저장 뒤에 새로 생긴
    #: 미션까지 체크로 보인다(#1716). 이 컬럼 이전에 저장된 행은 NULL — 앱이 옛
    #: 추정으로 되살린다.
    completed_keys_json: Mapped[str | None] = mapped_column(Text, nullable=True)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class TrainerFollowUpTask(Base):
    """트레이너가 고객별로 남기는 후속 관리 할 일. (#869)

    회원 상세에서 상태를 확인하다 "며칠 뒤 다시 볼 것"을 남겨 두는 자리다.
    메모(`TrainerClientMemo`)와 나누는 까닭은 묻는 질문이 다르기 때문이다 —
    메모는 "이 고객에 대해 무엇을 알아 두었나"이고, 여기 있는 행은 "언제까지
    무엇을 해야 하나"다. 그래서 예정일과 완료 상태를 갖고, 대시보드가 오늘
    처리할 목록으로 읽는다.

    범용 업무 관리가 아니다. 우선순위·담당자 배정·태그는 두지 않고, 트레이너
    본인이 담당 고객에 대해 남기는 최소 업무 큐만 표현한다.

    `context_type` 은 할 일에서 어느 화면으로 갈지의 힌트다. 새 deep-link 체계를
    만들지 않고 기존 route 를 고르는 값이라 열어 두지 않고 못 박는다 — 앱이 모르는
    값이 오면 이동할 곳이 없다.

    `client_request_id` 는 생성 시도 단위 멱등키다. 네트워크가 끊겨 재시도한
    등록이 같은 할 일을 두 번 만들면 대시보드에 같은 줄이 겹쳐 뜬다.
    """

    __tablename__ = "trainer_follow_up_tasks"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    trainer_id: Mapped[str] = mapped_column(
        # 단독 인덱스를 두지 않는다 — 아래 (trainer_id, status, due_date) 인덱스가
        # 선행 컬럼으로 커버한다(`TrainerClientMemo.trainer_id` 와 같은 규약).
        ForeignKey("users.id", ondelete="CASCADE")
    )
    member_id: Mapped[str] = mapped_column(
        # 회원 삭제 CASCADE 가 이 컬럼으로 행을 찾으므로 단독 인덱스가 필요하다.
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    title: Mapped[str] = mapped_column(String(200))
    #: 확인 예정일 `YYYY-MM-DD`(KST). `TrainerSchedule.date` 와 같은 표기라
    #: 문자열 비교로 오늘/지난 항목을 가른다.
    due_date: Mapped[str] = mapped_column(String(10))
    #: 'pending' | 'completed'
    status: Mapped[str] = mapped_column(String(16), default="pending")
    #: 'general' | 'diet' | 'exercise' | 'message' | 'program' | 'schedule'
    context_type: Mapped[str] = mapped_column(String(16), default="general")
    client_request_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
    #: 완료 처리 시각. 미완료는 NULL 이라 상태와 시각이 어긋날 수 없다.
    completed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    __table_args__ = (
        UniqueConstraint(
            "trainer_id",
            "client_request_id",
            name="uq_trainer_follow_up_task_client_request",
        ),
        # 응답 스키마가 두 값만 받는다. 다른 값이 한 행이라도 들어가면 그 트레이너의
        # 할 일 **목록 전체**가 검증 실패로 500 이 된다(`ck_trainer_client_memo_source`
        # 와 같은 이유).
        CheckConstraint(
            "status IN ('pending', 'completed')",
            name="ck_trainer_follow_up_task_status",
        ),
        CheckConstraint(
            "context_type IN "
            "('general', 'diet', 'exercise', 'message', 'program', 'schedule')",
            name="ck_trainer_follow_up_task_context",
        ),
        # 대시보드가 읽는 질의 그대로다 — 내 미완료 할 일을 예정일 순으로.
        Index(
            "ix_trainer_follow_up_tasks_queue",
            "trainer_id",
            "status",
            "due_date",
        ),
    )


class RoutineHistory(Base):
    """회원의 운동 완료 기록 — 프론트 ClientRoutineHistory 대응.

    회원이 자율 운동을 완료하거나(회원 앱), 트레이너가 PT 세션을 완료 처리하면
    (스케줄 완료 루프) 생성된다. date_label 은 저장하지 않고 date 로부터 파생한다.
    """

    __tablename__ = "routine_history"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    member_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    # 트레이너 지도 세션이면 트레이너, 자율 운동이면 NULL.
    trainer_id: Mapped[str | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )
    date: Mapped[str] = mapped_column(String(10), index=True)  # YYYY-MM-DD
    kind_label: Mapped[str] = mapped_column(
        String(50), default=""
    )  # 'PT 세션 · 트레이너 지도'
    completion_rate: Mapped[int] = mapped_column(Integer, default=0)  # 0..100
    exercises_json: Mapped[str] = mapped_column(
        Text, default="[]"
    )  # ["레그프레스 3세트", ...]
    client_feedback: Mapped[str] = mapped_column(Text, default="")
    trainer_note: Mapped[str] = mapped_column(Text, default="")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class ChatMessage(Base):
    """트레이너↔회원 채팅 메시지 — 프론트 ClientChatMessages 대응.

    스레드는 (trainer_id, member_id) 로 식별. sender 는 백엔드 진실값 'trainer'|'member'
    로 저장하고, 트레이너 API 응답에선 프론트 계약에 맞춰 'client' 로 노출한다.
    read_at 으로 양쪽 미확인 수를 계산.
    """

    __tablename__ = "chat_messages"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    trainer_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    member_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    sender: Mapped[str] = mapped_column(String(20))  # trainer|member
    body: Mapped[str] = mapped_column(Text)
    # 한 번의 발신 시도에 클라이언트가 붙이는 멱등키. NULL 은 기존 앱 요청이며
    # 유니크 제약 밖에 남는다. sender 까지 scope 에 넣어 양방향이 같은 문자열 키를
    # 우연히 만들어도 서로 충돌하지 않게 한다.
    client_request_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    # #778: 주간 리포트 PDF 1종만 지원한다. 기존 텍스트 메시지는
    # 모두 NULL이므로 기존 응답과 조회 흐름을 그대로 유지한다.
    attachment_type: Mapped[str | None] = mapped_column(String(20), nullable=True)
    attachment_file_name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    attachment_file_id: Mapped[str | None] = mapped_column(
        String(64), nullable=True, unique=True, index=True
    )
    attachment_file_size: Mapped[int | None] = mapped_column(Integer, nullable=True)
    # 이 메시지가 주간 리포트 전송 안내라면 그 주 월요일 `YYYY-MM-DD`. (#1600)
    #
    # 첨부만으로는 판단할 수 없다 — 리포트는 PDF 없이 본문으로도 나가고(`/report/send`),
    # 파일명에서 주차를 파내면 표시용 문자열이 곧 로직이 된다. 그래서 보내는 쪽이
    # 실어 보낸 값을 그대로 들고 있는다. 일반 대화는 NULL 이라 예전 행과 조회
    # 흐름은 그대로다.
    report_week_start: Mapped[str | None] = mapped_column(String(10), nullable=True)
    read_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), index=True
    )

    __table_args__ = (
        UniqueConstraint(
            "trainer_id",
            "member_id",
            "sender",
            "client_request_id",
            name="uq_chat_messages_client_request",
        ),
    )


class TrainerSchedule(Base):
    """트레이너의 일일 타임라인 슬롯 — 프론트 TrainerScheduleEntries 대응.

    회원과 매칭된 슬롯은 member_id 를 갖고, 상담/신규/공백은 client_name(표시용)만
    갖는다. status: 예정|완료|취소|노쇼|공백. program_json: [{name,sets,reps,weight}].

    `취소`·`노쇼` 는 삭제와 다르다(#871). 삭제는 **잘못 만든 데이터를 없애는 일**
    이고, 취소·노쇼는 실제로 있었던 약속이 진행되지 않았다는 **업무 기록**이다.
    둘을 같은 동작으로 두면 "왜 그 PT 가 진행되지 않았나" 가 사라져, 나중에 회원의
    낮은 완료율이 본인의 미이행 때문인지 트레이너 사정의 취소 때문인지 구분할 수
    없다.

    상태값은 **DB 에 저장되는 계약값**이라 한국어 그대로 둔다 — 앱과 서비스가 이
    문자열로 거르므로(`ScheduleStatus`, `status == "예정"`) 표기 체계를 갈아 끼우면
    기존 행이 어느 질의에도 걸리지 않는다. 새 상태도 같은 체계를 따른다.
    """

    __tablename__ = "trainer_schedule"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    trainer_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    member_id: Mapped[str | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )
    date: Mapped[str] = mapped_column(String(10), index=True)  # YYYY-MM-DD
    time: Mapped[str] = mapped_column(String(10), default="")  # "10:00"
    client_name: Mapped[str] = mapped_column(
        String(100), default=""
    )  # 표시용(상담/신규 포함)
    type: Mapped[str] = mapped_column(String(30), default="")  # 1:1 PT|상담|...
    duration_minutes: Mapped[int] = mapped_column(Integer, default=0)
    status: Mapped[str] = mapped_column(
        String(10), default="예정"
    )  # 예정|완료|취소|노쇼|공백
    # 취소·노쇼는 "그때 무슨 일이 있었나" 를 남기는 기록이라 시각을 함께 둔다.
    # 미완료 상태는 NULL 이라 상태와 시각이 어긋날 수 없다(#871).
    cancelled_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    #: 누가 취소했나 — ''(해당 없음)|member|trainer|other. 트레이너 사정의 취소를
    #: 회원의 미이행으로 읽지 않으려면 주체가 남아 있어야 한다.
    cancellation_source: Mapped[str] = mapped_column(String(16), default="")
    #: 트레이너가 남기는 짧은 사유. 회원에게 보내는 문구가 아니라 내부 기록이다.
    cancellation_reason: Mapped[str] = mapped_column(String(200), default="")
    no_show_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    note: Mapped[str] = mapped_column(Text, default="")
    program_json: Mapped[str] = mapped_column(Text, default="[]")
    # 완료한 세션의 프로그램을 회원에게 보낸 시각. NULL 은 아직 보내지 않은
    # 것이다 — 화면의 '전송됨' 표시와 재전송 방지가 이 값을 읽는다(#822).
    program_sent_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    sort_order: Mapped[int] = mapped_column(Integer, default=0)
    # 트레이너의 예약 생성 시도 단위 멱등키. 다른 create operation 과는 테이블이
    # 달라 같은 문자열을 써도 충돌하지 않는다. NULL 은 구버전 요청 호환용이다.
    client_request_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    # 한 번의 반복 설정으로 함께 만들어진 회차들을 잇는 값(#870). 단일 일정은
    # NULL 이다.
    #
    # 규칙(요일·종료 기준)을 저장하는 별도 표를 두지 않는다. 만들고 나면 각 회차는
    # **독립된 약속**이라 개별로 옮기고 지우는 것이 실제 운영이고, 규칙을 남겨 두면
    # 그 규칙과 실제 회차가 조용히 어긋난다. 여기서 필요한 것은 "이 회차들이 한
    # 번에 잡힌 것" 이라는 사실뿐이다.
    series_id: Mapped[str | None] = mapped_column(
        String(64), nullable=True, index=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )

    __table_args__ = (
        UniqueConstraint(
            "trainer_id",
            "client_request_id",
            name="uq_trainer_schedule_client_request",
        ),
        # 응답 스키마(`ScheduleSessionOut.cancellation_source`)가 네 값만 받는다.
        # 다른 값이 한 행이라도 들어가면 그 트레이너의 **하루 전체**가 검증 실패로
        # 500 이 된다.
        CheckConstraint(
            "cancellation_source IN ('', 'member', 'trainer', 'other')",
            name="ck_trainer_schedule_cancellation_source",
        ),
    )


class TrainerReservationSlot(Base):
    """A trainer-owned, member-bookable calendar slot."""

    __tablename__ = "trainer_reservation_slots"
    __table_args__ = (
        CheckConstraint("capacity > 0", name="ck_reservation_slot_capacity_positive"),
        CheckConstraint(
            "remaining >= 0 AND remaining <= capacity",
            name="ck_reservation_slot_remaining_range",
        ),
        # 스케줄 탭의 `TrainerSchedule.type` 과 같은 계약값이다(#1083). 슬롯은
        # 늘 한 사람 몫이라 정원을 고를 이유가 없어졌지만, 무슨 약속인지는
        # 여전히 골라야 한다 — 회원 예약이 만드는 일정이 그 종류를 그대로
        # 물려받는다.
        CheckConstraint(
            "session_type IN ('1:1 PT', '상담')",
            name="ck_reservation_slot_session_type",
        ),
        Index("ix_reservation_slots_trainer_starts", "trainer_id", "starts_at"),
    )

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    trainer_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    starts_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    duration_minutes: Mapped[int] = mapped_column(
        Integer, nullable=False, server_default="60", default=60
    )
    capacity: Mapped[int] = mapped_column(Integer)
    remaining: Mapped[int] = mapped_column(Integer)
    session_type: Mapped[str] = mapped_column(
        String(16), server_default="1:1 PT", default="1:1 PT"
    )
    is_closed: Mapped[bool] = mapped_column(
        Boolean, nullable=False, server_default=false(), default=False
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class TrainerReservation(Base):
    """A member's persisted booking for one trainer slot."""

    __tablename__ = "trainer_reservations"
    __table_args__ = (
        UniqueConstraint("member_id", "slot_id", name="uq_reservation_member_slot"),
        Index("ix_reservations_slot_status", "slot_id", "status"),
    )

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    member_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="RESTRICT"), index=True
    )
    slot_id: Mapped[str] = mapped_column(
        ForeignKey("trainer_reservation_slots.id", ondelete="RESTRICT"), index=True
    )
    schedule_id: Mapped[str] = mapped_column(
        ForeignKey("trainer_schedule.id", ondelete="RESTRICT"), unique=True
    )
    status: Mapped[str] = mapped_column(
        String(20), nullable=False, server_default="booked", default="booked"
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    cancelled_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )


class AuditLog(Base):
    """보안 감사 로그 — 인증/관리자 이벤트 추적.

    user_id 는 FK 를 두지 않는다(사용자가 삭제돼도 감사 기록은 남아야 하므로).
    event 예: auth.login, auth.register, auth.social, admin.public_doc_upload.
    """

    __tablename__ = "audit_logs"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    event: Mapped[str] = mapped_column(String(50), index=True)
    user_id: Mapped[str | None] = mapped_column(String(64), nullable=True, index=True)
    ip: Mapped[str] = mapped_column(String(64), default="")
    success: Mapped[bool] = mapped_column(Boolean, default=True)
    detail: Mapped[str] = mapped_column(Text, default="")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class RevokedRefreshToken(Base):
    """폐기된 refresh 토큰 — 로그아웃과 회전이 여기에 이름을 적는다.

    JWT 는 서버가 상태를 두지 않는 대신 **한 번 발급하면 만료까지 유효**하다.
    그래서 로그아웃이 로컬 저장소만 지우면, 그 사이 새어 나간 토큰은 남은 수명
    (기본 30일) 동안 계속 통한다. 이 표에 적힌 `jti` 는 `/auth/refresh` 에서
    거부되어 세션이 그 자리에서 끊긴다(#966).

    담는 것은 **아직 만료되지 않은 토큰뿐**이다. `expires_at` 이 지난 항목은
    이미 JWT 검증에서 걸리므로 폐기 여부를 물을 이유가 없고, 새 폐기가 생길 때마다
    정리한다(`token_revocation.purge_expired`).
    """

    __tablename__ = "revoked_refresh_tokens"

    #: 토큰의 `jti` 클레임. 토큰 자체가 아니라 이름만 저장한다.
    jti: Mapped[str] = mapped_column(String(64), primary_key=True)
    user_id: Mapped[str] = mapped_column(
        String(64), ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    #: 이 토큰이 스스로 만료되는 시각. 정리 기준.
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    revoked_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class AiConversation(Base):
    """AI 코치(온이)와의 대화 스레드.

    앱에는 대화 목록 UI 가 없고 채팅 시트 하나만 있으므로, 사용자당 활성 스레드
    1개를 get-or-create 해서 쓴다(coach_service 참고). 나중에 스레드 목록이 필요해질
    때를 대비해 테이블은 분리해 둔다 — 그때 컬럼 추가 없이 archived_at 만 채우면 된다.

    트레이너↔회원 채팅(chat_messages)과는 다른 도메인이다. 이쪽은 사람 간 대화가
    아니라 LLM 대화라 sender 대신 role(user|coach)을 쓰고 근거 문서를 함께 남긴다.
    """

    __tablename__ = "ai_conversations"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    #: 누가 나눈 대화인가 (#588). NULL 이면 회원 본인의 대화 — 회원 앱이 읽는 것.
    #: 값이 있으면 그 트레이너가 이 회원에 대해 물어본 대화다. `user_id` 는 어느
    #: 쪽이든 **검색 스코프**(누구 기록을 근거로 삼는가)라 항상 회원이다.
    trainer_id: Mapped[str | None] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=True
    )
    #: 비우면 활성 스레드. 값이 있으면 보관된 스레드(현재는 쓰지 않음).
    archived_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    # NULL 은 일반 UNIQUE 에서 서로 다른 값으로 취급된다. 회원 본인 스레드와
    # 트레이너별 스레드를 별도 부분 인덱스로 묶어 활성 대화를 하나만 허용한다.
    __table_args__ = (
        Index(
            "uq_ai_conversations_active_member",
            "user_id",
            unique=True,
            postgresql_where=text("archived_at IS NULL AND trainer_id IS NULL"),
        ),
        Index(
            "uq_ai_conversations_active_trainer",
            "user_id",
            "trainer_id",
            unique=True,
            postgresql_where=text("archived_at IS NULL AND trainer_id IS NOT NULL"),
        ),
    )


class AiMessage(Base):
    """AI 코치 대화의 한 줄.

    `sources_json` 은 그 답변의 근거로 쓰인 공공 가이드라인 제목들이다. 답변과 함께
    저장해야 대화를 복원했을 때도 근거 표시가 남는다(재접속 시 근거가 사라지면
    "왜 이렇게 답했는지"를 되짚을 수 없다).
    """

    __tablename__ = "ai_messages"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    conversation_id: Mapped[str] = mapped_column(
        ForeignKey("ai_conversations.id", ondelete="CASCADE"), index=True
    )
    #: 대화 내 순번(0부터). created_at 으로 정렬하면 안 되기 때문에 둔다 —
    #: PostgreSQL 의 now() 는 트랜잭션 시각이라 같은 커밋에 저장되는 질문과 답변이
    #: **동일한 created_at** 을 갖고, 그러면 정렬이 랜덤한 id 순으로 무너져 답변이
    #: 질문보다 먼저 보인다(실제로 그렇게 나왔다).
    seq: Mapped[int] = mapped_column(Integer, default=0)
    role: Mapped[str] = mapped_column(String(10))  # user|coach
    content: Mapped[str] = mapped_column(Text)
    sources_json: Mapped[str] = mapped_column(Text, default="[]")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )

    __table_args__ = (
        UniqueConstraint("conversation_id", "seq", name="uq_ai_messages_convo_seq"),
    )


class WeeklyChallenge(Base):
    """주간 운동 챌린지 참가 기록 — 회원이 참가한 주 하나당 한 줄. (#1789)

    포인트를 걸고(`stake`) 한 주(KST 월~일) 운동 목표를 채우면 `reward` 를 돌려받는다.
    참가는 그 주 월·화요일에만, 한 주에 한 번이다(`(user_id, week_start)` 유니크).

    - `goal` 은 참가할 때의 주간 운동 횟수 목표 사본이다. 참가 뒤 목표를 바꿔도
      그 주 챌린지는 참가할 때 목표로 판정한다.
    - `status` 는 active(진행 중)|succeeded|failed. 스케줄러가 없어 **주가 끝난 뒤
      읽는 쪽이 판정한다**(`weekly_challenge_service.settle_due`).
    - `final_days` 는 판정 때 센 운동한 날 수다. 판정 뒤 지난 주 기록이 바뀌어도
      결과 화면이 판정과 어긋나지 않게 남긴다.
    - 포인트 움직임은 `points_ledger` 에 `source_type='weekly_challenge'` 로 남는다 —
      참가 `spend`, 성공 `earn`.
    """

    __tablename__ = "weekly_challenges"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    #: 그 주의 월요일(KST, YYYY-MM-DD). `exercise_sessions.week_start` 와 같은 표기.
    week_start: Mapped[str] = mapped_column(String(10))
    goal: Mapped[int] = mapped_column(Integer)
    stake: Mapped[int] = mapped_column(Integer)
    reward: Mapped[int] = mapped_column(Integer)
    status: Mapped[str] = mapped_column(
        String(12), default="active", server_default="active"
    )  # active|succeeded|failed
    final_days: Mapped[int | None] = mapped_column(Integer, nullable=True)
    #: 참가 시도 단위 멱등키. 응답을 못 받고 다시 누른 참가가 두 번 걸지 않는다.
    client_request_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    joined_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    settled_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    __table_args__ = (
        CheckConstraint(
            "status IN ('active', 'succeeded', 'failed')",
            name="ck_weekly_challenges_status",
        ),
        CheckConstraint("goal BETWEEN 1 AND 7", name="ck_weekly_challenges_goal"),
        CheckConstraint("stake > 0", name="ck_weekly_challenges_stake"),
        CheckConstraint("reward > 0", name="ck_weekly_challenges_reward"),
        UniqueConstraint(
            "user_id", "week_start", name="uq_weekly_challenges_user_week"
        ),
        UniqueConstraint(
            "user_id",
            "client_request_id",
            name="uq_weekly_challenges_client_request",
        ),
        Index("ix_weekly_challenges_user_status", "user_id", "status"),
    )
