"""
트레이너 도메인 데모 시드.

트레이너 앱의 데모/데이터 공유 데모를 위해 트레이너 계정 1명(김트레이너)과
담당 회원 15명(#572), 그리고 담당 링크를 시드한다. 상세 기록(끼니별 음식·
피드백·채팅·스케줄)은 앞의 3명만 가지고, 나머지는 로스터·차트가 동작할 만큼의
주간 지표만 가진다(seed_roster).

핵심(진짜 데이터 공유): 여기서 만드는 회원은 실제 회원 User 다. 이후 이슈에서
이 회원들이 회원 앱으로 남긴 식단/운동/바이탈을 트레이너가 그대로 읽는다.
따라서 고객 식단 등을 여기서 복제하지 않는다.

멱등: 모든 삽입은 id·이메일 존재 검사 후 스킵한다. 같은 이메일을 가진 다른 id 의
사용자가 이미 있으면(users.email 유니크) 삽입을 건너뛰어 기동 실패를 막는다.
seed_demo_data 가 켜졌을 때만 호출된다. 데모 로그인 비밀번호는 설정값
(DEMO_LOGIN_PASSWORD)에서 읽는다 — 운영에서 데모 시드를 켜면 강한 값이 강제된다.
"""
from __future__ import annotations

import json
import logging

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.services import health_focus
from app.core.config import get_settings
from app.core.security import hash_password
from app.db.session import SessionLocal
from app.models import models

logger = logging.getLogger(__name__)

#: PostgreSQL unique_violation. 동시 기동이 같은 결정론적 id/이메일을 경쟁 삽입할 때만
#: 나는 코드로, 이때만 '이미 다른 인스턴스가 넣음'으로 보고 넘긴다.
_PG_UNIQUE_VIOLATION = "23505"


def _safe_commit(db: Session, context: str) -> None:
    """시드 커밋. 동시 기동 경쟁의 UNIQUE 충돌(23505)만 무시하고, FK(23503)·NOT NULL
    (23502)·CHECK 등 진짜 오류는 다시 발생시켜(데이터가 롤백된 채 조용히 기동 계속 방지)
    기동을 실패시킨다."""
    try:
        db.commit()
    except IntegrityError as e:
        db.rollback()
        sqlstate = getattr(getattr(e, "orig", None), "sqlstate", None)
        if sqlstate != _PG_UNIQUE_VIOLATION:
            raise
        logger.warning("%s — 동시 기동 경쟁으로 롤백 후 스킵.", context, exc_info=True)


# 트레이너 데모 계정
TRAINER_ID = "trainer-demo"
TRAINER_EMAIL = "trainer@oncare.com"
TRAINER_NAME = "김트레이너"

# 담당 회원: (user_id, email, name, health_focus, active, dormant, sort_order)
#
# health_focus 는 회원 건강 목표(`HealthProfile.conditions`, 최대 2개)다(#1818). 예전에는
# 트레이너가 적은 자유 문장(`산후 체력 회복`, `마라톤 완주 준비`)이었고, 회원앱이 고르는
# 목표와 따로 놀았다. 트레이너 로스터는 이제 회원 건강 목표를 읽는다.
# 김민수는 회원 앱 데모 사용자(user-7d4e9a2c5f18)와 동일 계정을 공유한다.
#
# `active` 와 `dormant` 는 다른 축이다(#707). 화면에는 둘 다 '휴면'으로 보이지만
# 뜻이 다르므로 시드도 두 경우를 각각 남긴다:
#   * 박성호 — 담당 관계가 해제된 과거 회원(active=False). 회원측 '내 코치'가
#     비어 있어야 하고, 트레이너가 다시 활성으로 되돌릴 수 없다.
#   * 문가영 — 담당은 그대로인데 트레이너가 휴면으로 내린 회원(dormant=True).
#     활성/휴면 전환을 실 API 콘솔에서 그대로 눌러 볼 수 있는 fixture 다.
_MEMBERS: list[tuple[str, str, str, str, bool, bool, int]] = [
    ("user-7d4e9a2c5f18", "minsu@oncare.com", "김민수", "체중 감량, 혈압 관리", True, False, 1),
    ("user-jisu", "jisu@oncare.com", "이지수", "체중 감량, 체력 강화", True, False, 2),
    ("user-sungho", "sungho@oncare.com", "박성호", "근력 향상", False, False, 3),
    # 4~15: 트레이너 웹 목업 로스터와 같은 명단(#572). 주간 지표는 seed_roster 가
    # 채운다 — 화면 상태(나트륨 초과·이행률 저조·휴면·답장 대기)를 실 API 에서도
    # 재현하기 위한 fixture 다.
    ("user-hayun", "hayun@oncare.demo", "정하윤", "체력 강화, 재활", True, False, 4),
    ("user-woojin", "woojin@oncare.demo", "최우진", "체력 강화", True, False, 5),
    ("user-kangseoyeon", "kangseoyeon@oncare.demo", "강서연", "체중 감량", True, False, 6),
    ("user-dohyun", "dohyun@oncare.demo", "임도현", "자세 교정", True, False, 7),
    ("user-sera", "sera@oncare.demo", "오세라", "혈압 관리", True, False, 8),
    ("user-junhyuk", "junhyuk@oncare.demo", "배준혁", "체력 강화, 운동 습관", True, False, 9),
    ("user-yuna", "yuna@oncare.demo", "신유나", "재활", True, False, 10),
    ("user-jiho", "jiho@oncare.demo", "한지호", "식습관 개선, 운동 습관", True, False, 11),
    ("user-gayoung", "gayoung@oncare.demo", "문가영", "체력 강화", True, True, 12),
    ("user-taekyung", "taekyung@oncare.demo", "류태경", "근력 향상, 식습관 개선", True, False, 13),
    ("user-seojin", "seojin@oncare.demo", "백서진", "식습관 개선", True, False, 14),
    ("user-eunchae", "eunchae@oncare.demo", "노은채", "운동 습관", True, False, 15),
]

#: 담당 회원의 성별(male|female). 트레이너 로스터 카드가 이름 옆에 적는 값이다.
#:
#: 저장된 값이 없으면 트레이너 앱이 회원 id 로 표시값을 지어내는데, 데모
#: (`seed-client-8`)와 실 API(`user-sera`)가 서로 다른 id 를 써서 같은 회원이
#: 모드에 따라 다른 성별로 떴다(#960). 여기 값이 정답이고, 앱의 계산은 성별이
#: 비어 있는 회원에게만 남는다.
_MEMBER_GENDERS: dict[str, str] = {
    "user-7d4e9a2c5f18": "male",            # 김민수
    "user-jisu": "female",          # 이지수
    "user-sungho": "male",          # 박성호
    "user-hayun": "female",         # 정하윤
    "user-woojin": "male",          # 최우진
    "user-kangseoyeon": "female",   # 강서연
    "user-dohyun": "male",          # 임도현
    "user-sera": "female",          # 오세라
    "user-junhyuk": "male",         # 배준혁
    "user-yuna": "female",          # 신유나
    "user-jiho": "male",            # 한지호
    "user-gayoung": "female",       # 문가영
    "user-taekyung": "female",      # 류태경
    "user-seojin": "male",          # 백서진
    "user-eunchae": "female",       # 노은채
}

_CERTIFICATIONS = ["생활스포츠지도사 2급", "퍼스널트레이닝 CPT", "스포츠 영양사"]


def _demo_password_hash() -> str:
    return hash_password(get_settings().demo_login_password)


def _email_taken_by_other(db: Session, email: str, user_id: str) -> bool:
    """이 이메일을 가진 '다른 id' 의 사용자가 이미 있으면 True(유니크 충돌 예방)."""
    other = db.scalar(
        select(models.User.id).where(models.User.email == email, models.User.id != user_id)
    )
    return other is not None


def seed_trainer_domain() -> None:
    db: Session = SessionLocal()
    try:
        _seed_trainer_account(db)
        _seed_member_accounts(db)
        _seed_client_links(db)
    finally:
        db.close()


def _seed_trainer_account(db: Session) -> None:
    """트레이너 User + TrainerProfile(멱등, 이메일·역할 충돌 안전)."""
    trainer = db.scalar(select(models.User).where(models.User.id == TRAINER_ID))
    if trainer is not None:
        # 기존 ID 가 트레이너 데모와 역할/이메일이 다르면(예: 회원 계정이 선점) 프로필을
        # 붙이지 않는다 — 남의 계정을 트레이너로 오염시키지 않도록.
        if trainer.role != "trainer" or trainer.email != TRAINER_EMAIL:
            logger.warning(
                "기존 %s 계정이 트레이너 데모와 역할/이메일 불일치(role=%s) — 프로필 시드 스킵.",
                TRAINER_ID, trainer.role,
            )
            return
    else:
        if _email_taken_by_other(db, TRAINER_EMAIL, TRAINER_ID):
            logger.warning(
                "트레이너 데모 이메일 %s 가 다른 계정에 선점됨 — 트레이너 시드 스킵.",
                TRAINER_EMAIL,
            )
            return
        trainer = models.User(
            id=TRAINER_ID,
            email=TRAINER_EMAIL,
            name=TRAINER_NAME,
            hashed_password=_demo_password_hash(),
            role="trainer",
        )
        db.add(trainer)
        db.flush()

    profile = db.scalar(
        select(models.TrainerProfile).where(models.TrainerProfile.trainer_id == TRAINER_ID)
    )
    if profile is None:
        db.add(models.TrainerProfile(
            trainer_id=TRAINER_ID,
            phone="010-1234-5678",
            specialty="퍼스널 트레이너",
            # 추천 레일 노출 조건(#324). 비어 있으면 /trainers/recommended 에서 빠진다.
            recommend_reason="혈압 관리와 운동 병행 지도",
            career_years=7,
            intro=(
                "혈압 관리와 체중 감량 전문 트레이너입니다. 고객 맞춤형 AI 루틴으로 "
                "안전하고 효과적인 운동을 도와드려요."
            ),
            certifications_json=json.dumps(_CERTIFICATIONS, ensure_ascii=False),
            gym_name="온케어짐 신촌점",
            gym_address="서울 서대문구 신촌로 120",
            gym_hours="06:00 – 23:00",
            gym_phone="02-1234-5678",
        ))
    elif not profile.recommend_reason:
        # 프로필이 이미 있으면 위 블록을 건너뛰므로, 나중에 추가된 컬럼은 영영 빈 채로
        # 남는다. 추천 사유가 비면 /trainers/recommended 에서 빠지므로 백필한다(#324).
        profile.recommend_reason = "혈압 관리와 운동 병행 지도"
    _safe_commit(db, "트레이너 데모 계정 시드 충돌")


def _seed_member_accounts(db: Session) -> None:
    """담당 회원 User(멱등, 이메일 충돌 안전). user-7d4e9a2c5f18 는 기존 데모 시드가 만든다."""
    for user_id, email, name, _goal, _active, _dormant, _order in _MEMBERS:
        existing = db.scalar(select(models.User).where(models.User.id == user_id))
        if existing is not None:
            # 비밀번호가 비어 있으면 채운다. 이 시드보다 먼저 도는 데모 사용자 시드가
            # 예전에 김민수를 빈 해시로 만들었고, 그냥 건너뛰면 이미 볼륨을 가진
            # 개발자는 재기동해도 영영 로그인할 수 없다.
            #
            # 단 **이 id 가 진짜 데모 계정일 때만** 채운다. id 만 보고 채우면, 다른
            # 이메일·역할의 계정이 이 id 를 선점한 경우 그 계정에 널리 알려진 데모
            # 비밀번호로 로그인할 수단을 새로 만들어 주게 된다. 위 트레이너 시드가
            # 역할·이메일 불일치 시 기존 계정을 건드리지 않는 것과 같은 이유다.
            if not existing.hashed_password:
                if existing.email == email and existing.role == "member":
                    existing.hashed_password = _demo_password_hash()
                    logger.info(
                        "데모 회원 %s 의 빈 비밀번호를 데모 비밀번호로 채웠습니다.", user_id,
                    )
                else:
                    logger.warning(
                        "기존 %s 계정이 데모 회원과 이메일/역할 불일치"
                        "(email=%s, role=%s) — 비밀번호 백필 스킵.",
                        user_id, existing.email, existing.role,
                    )
            continue
        if _email_taken_by_other(db, email, user_id):
            logger.warning(
                "회원 데모 이메일 %s 가 다른 계정에 선점됨 — %s 시드 스킵.", email, user_id,
            )
            continue
        db.add(models.User(
            id=user_id,
            email=email,
            name=name,
            hashed_password=_demo_password_hash(),
            role="member",
        ))
    _safe_commit(db, "회원 데모 계정 시드 충돌")


def seed_member_genders() -> None:
    """담당 회원의 성별을 건강 프로필에 채운다(멱등).

    호출은 `seed_member_health_data` 의 마지막 단계다 — 성별이 담기는 자리가
    건강 프로필 행이라, 이 시드가 먼저 돌면 성별만 든 행이 생기고 위험도·영양
    목표를 넣는 쪽이 "이미 행이 있다"며 통째로 건너뛴다. 같은 이유로 계정 시드
    (`seed_trainer_domain`)가 아니라 건강 데이터 시드에 붙어 있어야, 그 시드를
    다시 돌리는 경로(계정 복구 등)에서 성별도 함께 돌아온다.
    """
    db: Session = SessionLocal()
    try:
        _seed_member_genders(db)
    finally:
        db.close()


def _seed_member_genders(db: Session) -> None:
    """[seed_member_genders] 본문 — 성별과 건강 목표(#1818). 이미 값이 있으면 건드리지 않는다 — 트레이너나
    회원이 입력한 값이 시드로 덮이면, 화면에서 고친 것이 재기동마다 되돌아온다."""
    changed = False
    focus_by_member = {user_id: focus for user_id, _e, _n, focus, _a, _d, _o in _MEMBERS}
    for user_id, gender in _MEMBER_GENDERS.items():
        member = db.scalar(select(models.User).where(models.User.id == user_id))
        if member is None or member.role != "member":
            continue  # 계정 시드가 건너뛴 회원(이메일 충돌 등)
        profile = db.scalar(
            select(models.HealthProfile).where(models.HealthProfile.user_id == user_id)
        )
        focus = focus_by_member.get(user_id, "")
        if profile is None:
            db.add(models.HealthProfile(user_id=user_id, gender=gender, conditions=focus))
            changed = True
            continue
        if not profile.gender:
            profile.gender = gender
            changed = True
        # 건강 목표도 같은 규칙이다 — 비어 있을 때만 채워, 회원·트레이너가 고른 목표를
        # 재기동마다 덮지 않는다(#1818).
        if focus:
            filled = health_focus.with_focus_if_missing(profile.conditions, focus)
            if filled != profile.conditions:
                profile.conditions = filled
                changed = True
    if changed:
        _safe_commit(db, "회원 성별 시드 충돌")


def _seed_client_links(db: Session) -> None:
    """트레이너↔회원 담당 링크(멱등). 트레이너/회원 역할이 맞아야만 링크한다."""
    trainer = db.scalar(select(models.User).where(models.User.id == TRAINER_ID))
    if trainer is None or trainer.role != "trainer":
        # 트레이너 계정이 없거나(시드 스킵) 역할이 트레이너가 아니면 링크를 만들지 않는다.
        return
    for user_id, _email, _name, focus, active, dormant, order in _MEMBERS:
        link_id = f"tc-{TRAINER_ID}-{user_id}"
        if db.scalar(select(models.TrainerClient.id).where(models.TrainerClient.id == link_id)):
            continue
        member = db.scalar(select(models.User).where(models.User.id == user_id))
        if member is None:
            continue
        # 기존 ID 가 회원이 아니면(예: 트레이너 역할) 담당 링크를 만들지 않는다.
        if member.role != "member":
            logger.warning(
                "기존 %s 계정이 회원이 아님(role=%s) — 담당 링크 시드 스킵.",
                user_id, member.role,
            )
            continue
        db.add(models.TrainerClient(
            id=link_id,
            trainer_id=TRAINER_ID,
            member_id=user_id,
            # 옛 칸이라 화면이 읽지 않지만, 같은 값을 적어 두어 두 칸이 다른 말을 하지 않게 한다.
            goal=health_focus.focus_label(focus),
            active=active,
            dormant=dormant,
            sort_order=order,
        ))
    _safe_commit(db, "담당 링크 시드 충돌")
