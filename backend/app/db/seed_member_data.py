"""
담당 회원의 건강 데이터 데모 시드 — 트레이너 로스터/식단/기록을 실데이터로 채운다.

**데모/개발 전용 (실서비스 아님).** 이 시드는 `SEED_DEMO_DATA=true` 일 때만 실행된다
(init_db 게이팅). 실서비스(prod)는 `SEED_DEMO_DATA=false` 로 두어 여기서 만드는 고정
데모 계정(김민수 등)을 넣지 않고, **진짜 사용자가 앱에서 직접 만든 데이터만** 쌓이게
한다. 즉 이 파일은 데모/발표·개발·CI 재현용 고정 데이터이지, 운영 사용자 데이터가 아니다.

여기서 넣는 식단(DietEntry)·운동기록(RoutineHistory)은 "회원이 회원 앱에서 남긴
실제 데이터"다. 트레이너 API 는 이 데이터를 그대로 읽어 로스터를 집계하므로,
트레이너↔회원 데이터 공유가 시드 단계에서부터 실제로 성립한다.

김민수(`user-7d4e9a2c5f18`)만은 이 파일이 값을 만들지 않는다. 그는 사용자 앱의 데모 계정과
같은 사람이라 두 앱을 나란히 놓고 시연하는데, 세 곳이 각자 계산하니 같은 날짜의
숫자가 서로 달랐다(#757). 그의 하루는 `app/db/demo_fixture.py` 가 읽는 픽스처가
정하고, 여기서는 그것을 테이블에 옮기기만 한다. 나머지 회원은 아래 상수들이 만든다.

멱등 + 날짜 인식:
- 오늘 식단은 회원에게 오늘 DietEntry 가 없을 때만 3끼를 넣는다.
- 최근 6일 나트륨 추세는 해당 날짜에 DietEntry 가 없을 때만 1건씩 넣는다
  (이미 '오늘'로 들어갔던 날은 건너뛰어 중복 합산을 막는다).
- 운동기록은 회원에게 오늘 기록이 없을 때만 최근 3세션을 넣는다.
날짜가 넘어가면 자연히 '오늘'이 새로 시드되고 과거 데이터는 누적되어 실제 이력이 된다.
픽스처 회원은 다르게 움직인다 — 날짜가 넘어가면 그의 `seed-` 행을 지우고 픽스처를
다시 깐다. 픽스처는 "오늘로부터 며칠 전"으로 적혀 있어 그래야 하루씩 앞으로 미끄러진다.
"""
from __future__ import annotations

import json
import logging
import time
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from typing import TypeVar

from sqlalchemy import or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.services.health_focus import normalize_conditions
from app.core import clock
from app.core.config import get_settings
from app.db.demo_fixture import FixtureExercise, FixtureRoutine, load_fixture
from app.db.seed_trainer import TRAINER_ID, _MEMBERS
from app.db.session import SessionLocal
from app.models import models
from app.services import exercise_activity, exercise_types, points_service
from app.services.coach import personal_ingest
from app.services.coach.rag import has_personal_doc

logger = logging.getLogger(__name__)


#: PostgreSQL unique_violation. 동시 기동(멀티 인스턴스)이 같은 결정론적 id를 경쟁
#: 삽입할 때만 발생하는 코드로, 이때만 '이미 다른 인스턴스가 넣음'으로 보고 넘긴다.
_PG_UNIQUE_VIOLATION = "23505"


def _safe_commit(db: Session) -> None:
    """시드 커밋. 동시 기동이 같은 결정론적 id를 경쟁 삽입한 UNIQUE 충돌(23505)만
    무시하고 넘어간다. FK(23503)·NOT NULL(23502)·CHECK 등 진짜 오류는 데이터가 롤백된
    채 조용히 기동을 이어가면 안 되므로 다시 발생시켜 기동을 실패시킨다."""
    try:
        db.commit()
    except IntegrityError as e:
        db.rollback()
        sqlstate = getattr(getattr(e, "orig", None), "sqlstate", None)
        if sqlstate != _PG_UNIQUE_VIOLATION:
            raise
        logger.info("member seed commit skipped (already seeded by a concurrent start)")

# 회원별 오늘 3끼 (meal_type, 음식, 칼로리, 나트륨, 당류, 탄수화물, 단백질, 지방)
# — 프론트 seed 와 동일 수치.
# 하루 나트륨 합 == _SODIUM_WEEK[member][-1](오늘) 이 되도록 맞춰 둠.
#
# 김민수(`user-7d4e9a2c5f18`)는 여기 없다 — 그의 하루는 픽스처가 정한다(#757). 아래 상수는
# 전부 그를 뺀 나머지 회원용이다.
_TODAY_MEALS: dict[
    str, list[tuple[str, str, int, int, float, float, float, float]]
] = {
    "user-jisu": [
        ("breakfast", "그릭요거트, 과일", 280, 200, 38, 40, 15, 6),
        ("lunch", "현미밥, 불고기, 나물", 750, 980, 0, 90, 35, 20),
        ("dinner", "연어 샐러드", 650, 620, 0, 20, 40, 22),
    ],
    "user-sungho": [
        ("breakfast", "계란 3개, 토스트", 480, 520, 0, 35, 28, 24),
        ("lunch", "짜장면", 890, 1200, 55, 120, 25, 30),
        ("dinner", "삼겹살, 쌈채소", 730, 680, 0, 20, 45, 50),
    ],
}

# 최근 7일 일별 나트륨(오래된→오늘). 마지막 값은 오늘 3끼 합과 일치.
#: 시드가 채우는 과거 주 수(이번 주 포함) — `seed_roster` 와 같은 값이다.
_HISTORY_WEEKS = 12

#: 과거 주에 곱하는 계수 — `seed_roster` 의 같은 이름들과 값을 맞춘다.
#: 지표마다 갈라 둔 이유는 그쪽 주석에 적어 뒀다.
_SODIUM_FACTORS = (1.0, 0.96, 1.14, 0.82, 1.07, 0.78, 1.10)
_CALORIE_FACTORS = (1.0, 0.92, 1.28, 0.88, 1.04, 0.95, 1.13)
_SUGAR_FACTORS = (1.0, 1.12, 1.55, 0.88, 1.30, 0.96, 1.42)
_COMPLETION_FACTORS = (1.0, 0.94, 1.08, 0.9, 1.05, 0.97, 1.11)

#: 요일별 하루 섭취량(월→일). 여기에 주 계수를 곱한다.
_WEEKDAY_KCAL = (1710, 1830, 1560, 1900, 1680, 1450, 1600)
_WEEKDAY_SUGAR = (41.5, 28.0, 45.5, 33.0, 38.5, 22.0, 30.0)

#: 어제 하루의 합. 약속이 있어 칼로리·당류가 목표(2,000kcal·50g)를 넘는다.
#:
#: 요일이 아니라 **어제**에 못 박는다 — 요일에 못 박으면 데모를 여는 날에 따라
#: 넘긴 날이 이번 주 밖으로 밀려난다. 두 Flutter 앱의 데모 시드가 같은 합계를
#: 쓴다(트레이너 `seed_data.dart` 의 `_feast*`, 사용자 앱의 어제 큐레이션).
_FEAST_KCAL = 2380
_FEAST_SODIUM_MG = 2261
_FEAST_SUGAR_G = 63.0

_SODIUM_WEEK: dict[str, list[int]] = {
    "user-jisu": [1700, 1950, 1600, 1800, 2100, 1750, 1800],
    "user-sungho": [2600, 2500, 2300, 2450, 2200, 2550, 2400],
}

# 최근 운동 세션(최신순): (완료율, 종류라벨, 운동목록, 회원피드백, 트레이너메모).
# 오늘/이틀전/나흘전 날짜로 시드. PT 세션은 trainer_id 를 붙인다.
_HISTORY: dict[str, list[tuple[int, str, list[str], str, str]]] = {
    "user-jisu": [
        (100, "AI 개인운동",
         ["인터벌 런닝 25분 ✓", "스쿼트 3세트 · 12회 · 40kg ✓", "플랭크 3세트 · 3회 · 0kg ✓"],
         "런닝이 힘들었는데 다 했어요! 숨이 많이 찼어요",
         "심폐지구력 향상 중. 다음 주 런닝 강도 소폭 올릴 예정."),
        (100, "PT 세션 · 트레이너 지도",
         ["데드리프트 3세트 · 8회 · 55kg", "런지 3세트 · 12회 · 10kg", "코어 서킷 2세트 · 12회 · 0kg"],
         "데드리프트 자세 교정 도움 많이 됐어요!", ""),
        (67, "AI 개인운동", ["런닝 25분 ✓", "스쿼트 ✓", "플랭크 ✗ (피로)"],
         "마지막 플랭크는 너무 지쳐서 못 했어요", ""),
    ],
    "user-sungho": [
        (100, "PT 세션 · 트레이너 지도",
         ["벤치프레스 4세트 · 8회 · 65kg", "인클라인 덤벨 3세트 · 10회 · 26kg",
          "트라이셉스 딥 3세트 · 12회 · 0kg"],
         "가슴이 많이 타는 느낌이었어요. 좋았어요!",
         "벤치 중량 62.5kg → 65kg 도전 가능. 다음 PT 때 시도 예정."),
        (33, "AI 개인운동", ["벤치프레스 ✓", "데드리프트 ✗", "유산소 ✗"],
         "회사 일이 생겨서 벤치만 하고 나왔어요", ""),
        (0, "AI 개인운동", ["벤치프레스 ✗", "데드리프트 ✗", "유산소 ✗"],
         "못 갔어요 😓", ""),
    ],
}


def _valid_member_ids(db: Session) -> set[str]:
    """트레이너 데모에 실제로 링크되고 회원 역할인 member_id 집합.

    이메일 충돌 등으로 회원 계정/링크가 만들어지지 않았으면(#249 시드가 스킵) 그 회원의
    건강 데이터를 넣으면 FK 오류로 기동이 죽는다. 유효한 회원만 시드 대상으로 삼는다.
    """
    rows = db.execute(
        select(models.TrainerClient.member_id)
        .join(models.User, models.User.id == models.TrainerClient.member_id)
        .where(
            models.TrainerClient.trainer_id == TRAINER_ID,
            models.User.role == "member",
        )
    ).all()
    return {r[0] for r in rows}


# 회원별 채팅 스레드 (sender: trainer|client, text, days_ago) — 프론트 시드와 정렬.
#
# user-7d4e9a2c5f18 스레드는 회원 앱·트레이너 앱의 데모 시드와 **같은 대화**여야 한다.
# 김민수는 회원 앱 데모 사용자(user-7d4e9a2c5f18)와 같은 계정이라, 실서버로 붙여도
# 데모에서 보던 대화가 그대로 이어져야 하기 때문이다. 같은 목록이 아래 두 곳에
# 있다 — 한 곳만 고치면 그 파일의 테스트가 깨진다:
#   * frontend/flutter_trainer/lib/core/storage/seed_clients.dart (트레이너 시점)
#   * frontend/flutter/lib/features/member_coach/data/repositories/
#     mock_member_coach_repository.dart (회원 시점)
#
# days_ago 는 그 메시지가 며칠 전 것인지다. 전부 같은 시각에 몰아넣으면 사흘에
# 걸친 대화가 30분짜리 수다로 보이고, 화면이 날짜로 묶는 자리(하루치 AI 분석
# 안내)도 하나로 뭉친다.
_CHAT: dict[str, list[tuple[str, str, int]]] = {
    "user-7d4e9a2c5f18": [
        # 1일차.
        ("trainer", "민수님, 지난주 기록 정리해 봤는데 요일마다 이행률이 들쭉날쭉하네요. 바쁜 요일이 정해져 있나요?", 5),
        ("client", "화요일이랑 목요일이 야근이 많아요 😥", 5),
        ("trainer", "그럼 그 이틀은 15분짜리 짧은 루틴으로 바꿔 둘게요. 안 하는 것보다 훨씬 낫습니다", 5),
        ("client", "그 정도면 퇴근하고도 할 수 있을 것 같아요", 5),
        ("trainer", "혈압약 드시는 시간은 그대로시죠? 유산소가 그 시간과 겹치지 않게 잡을게요", 5),
        ("client", "네, 아침 8시 그대로예요", 5),
        ("trainer", "확인했어요. 화·목은 15분 저강도로 바꿔서 보냈습니다 🙂", 5),
        # 2일차.
        ("trainer", "민수님, 요즘 나트륨이 목표(2,000mg) 근처에서 자주 걸리네요. 국·찌개가 잦으신 편인가요?", 4),
        ("client", "회사 구내식당이라 국물이 늘 나와요 😅", 4),
        ("trainer", "국물만 절반 남기셔도 400~500mg은 빠져요. 그거 하나만 먼저 해보죠", 4),
        ("client", "오늘은 국물 안 마셨어요! 걷기도 25분 했습니다", 4),
        ("trainer", "좋아요 👏 그 한 가지만 지켜도 추이가 달라져요", 4),
        ("trainer", "내일 루틴은 걷기 20분으로 조금 늘려서 보냈어요. 주말까지 이 페이스로 가봐요", 4),
        # 3일차.
        ("trainer", "민수님, AI 식단 분석 잘 받았어요 👍 오늘 나트륨이 목표치를 좀 넘었는데 어떠셨어요?", 0),
        ("client", "찌개 먹을 때 국물을 많이 마셨나봐요 😅", 0),
        ("trainer", "그렇군요! 오늘 PT 후에 부상이나 불편한 데는 없으셨나요?", 0),
        ("client", "무릎이 가볍게 당기긴 했는데 괜찮아요", 0),
        ("trainer", "확인했어요. AI가 오늘 식단 기반으로 유산소 루틴을 추천했는데, 무릎 상태 감안해서 런닝 대신 걷기로 조정해서 보낼게요. 다음 PT 때 봐요 💪", 0),
    ],
    "user-jisu": [
        ("trainer", "지수님, AI 운동 데이터 수신했어요 — 오늘 인터벌 런닝 25분 완료! 컨디션은 어때요?", 0),
        ("client", "생각보다 괜찮았어요. 숨이 금방 차더라고요 😮‍💨", 0),
        ("trainer", "심폐 지구력 올라가는 과정이에요 💪 AI 분석 보니까 당류는 목표 안에 있고, "
                    "루틴 다음 주부터 근력 비중 늘려볼게요. 식단도 AI 추천 참고해서 업데이트해 드릴게요", 0),
    ],
    "user-sungho": [
        ("trainer", "성호님, 이번 주 운동 기록이 AI 쪽에서 안 잡히는데 몸은 괜찮으세요?", 0),
        ("client", "이번 주 일이 너무 많아서 못 갔어요 😓", 0),
        ("trainer", "이해해요! 대신 AI 식단 분석 보니까 나트륨이 좀 높더라고요. 주말에 30분 걷기라도 하면 "
                    "도움 돼요. AI가 그에 맞는 루틴 다시 짜줬으니까 앱에서 확인해보세요 🙂", 0),
    ],
}

# 픽스처가 없는 회원의 AI 배정 루틴 (name, minutes, type, reason, sets, reps, weight).
# 김민수(user-7d4e9a2c5f18)는 여기 없다 — 공유 픽스처의 `routines` 가 원본이다(#1199).
#
# 근력은 세트·횟수·중량을 칸으로 든다(#1276). 예전에는 그 값이 이름 안에 문자열로
# 박혀 있었고(`스쿼트 3세트`) 칸은 비어 있어서, 트레이너 화면이 배정을 `15분` 으로만
# 읽었다 — 세트는 이름에 있으니 옮겨 적을 수도, 세어 볼 수도 없는 값이었다. 맨몸
# 운동(플랭크)은 중량이 0 이다 — 두 앱의 중량 칸은 비울 수 없어(최솟값 0),
# 맨몸은 적지 않은 값이 아니라 0 으로 적은 값이다.
_ROUTINES: dict[
    str, list[tuple[str, int, str, str, int | None, int | None, float | None]]
] = {
    "user-jisu": [
        ("인터벌 런닝", 25, "유산소", "체지방 연소 효율↑", None, None, None),
        ("스쿼트", 15, "근력", "하체 근력 강화", 3, 12, 40.0),
        ("플랭크", 10, "근력", "코어 안정화", 3, 3, 0.0),
    ],
    "user-sungho": [
        ("벤치프레스", 20, "근력", "상체 근력 목표", 4, 8, 65.0),
        ("데드리프트", 15, "근력", "전신 근력 향상", 3, 8, 60.0),
        ("유산소 쿨다운", 10, "유산소", "나트륨 배출 지원", None, None, None),
    ],
}

# 회원별 이번 주 운동 세션 — (요일, 종류, 분, 칼로리).
#
# 김민수는 여기 없다 — 그의 운동은 픽스처가 날짜별 루틴 항목으로 갖고 있고, 세션은
# 그중 실제로 한 항목에서 나온다(#757). 지금은 다른 회원의 주간 세션이 없어 비어
# 있지만, 생기면 여기에 적는다.
_EXERCISE_WEEK: dict[str, list[tuple[str, str, int, int]]] = {}

# day_label → 요일 인덱스(월=0 … 일=6, date.weekday() 와 동일). 운동 시드는 이 인덱스로
# "오늘까지의 요일"만 넣어, 주중 실행 시 미래 요일이 이번 주 합계·streak 에 잡히는 것을 막는다.
_WEEKDAY_INDEX: dict[str, int] = {
    "월": 0, "화": 1, "수": 2, "목": 3, "금": 4, "토": 5, "일": 6,
}

# 사용자 앱 데모 회원(김민수)의 건강 프로필 — 프론트 MockMyHealthRepository/프로필 목업과
# 동일. 위험도·활동점수·기본정보 + 목표치는 구조화 컬럼(goal_*/daily_*)에 넣는다.
# conditions 는 건강 목표다(#1814) — 트레이너 앱이 이 회원의 목표로 보여 주는 `혈압 관리 · 체중 감량`
# 과 같다. 키(height_cm)·성별은 목업에 없어 비운다.
#: 이 파일이 예전에 데모 회원에게 넣던 질환 이름. 이미 시드된 DB 를 새 목표로 옮길 때 알아본다.
_LEGACY_DEMO_CONDITIONS = "고혈압, 당뇨 전단계"

_HEALTH_PROFILE: dict[str, dict] = {
    "user-7d4e9a2c5f18": {
        "risk_title": "고혈압·당뇨 위험 주의",
        "risk_body": "최근 혈압과 혈당 추세가 다소 높습니다. 식단·운동 관리에 신경 써주세요.",
        "risk_level": "medium",
        "conditions": "체중 감량, 혈압 관리",
        "phone": "010-1234-5678",
        "birth_date": "1990-01-15",
        "activity_points": points_service.DEMO_OPENING_POINTS,
        "activity_rank": 14,
        # 일일 영양 목표(프론트 프로필 목업과 동일)
        "daily_calories": 2000,
        "daily_sodium_mg": 2000,
        "daily_sugar_g": 50,
        "daily_carbs_g": 275,
        "daily_protein_g": 100,
        "daily_fat_g": 55,
        # 주간 운동 목표
        "weekly_workout_goal": 7,
        "weekly_exercise_minutes_goal": 150,
        "weekly_burn_goal": 1500,
        "onboarded": True,
    },
}


# 트레이너 오늘 타임라인 (time, client, member_id, type, duration, status, note, program).
# member_id 는 유효 회원일 때만 연결(아니면 표시용 이름만). 프론트 TRAINER_SCHEDULE 정렬.
_SCHEDULE: list[tuple[str, str, str | None, str, int, str, str, list[dict]]] = [
    ("10:00", "김민수", "user-7d4e9a2c5f18", "1:1 PT", 60, "완료", "무릎 컨디션 양호. 레그프레스 중량 소폭 증가 가능.", [
        {"name": "레그프레스", "type": "근력", "sets": 3, "reps": 12, "weight": 80},
        {"name": "레그컬", "type": "근력", "sets": 3, "reps": 12, "weight": 40},
        {"name": "카프레이즈", "type": "근력", "sets": 3, "reps": 20, "weight": 0},
        {"name": "하체 스트레칭", "type": "스트레칭", "duration": 10},
    ]),
    ("12:00", "이지수", "user-jisu", "1:1 PT", 50, "완료", "데드리프트 자세 안정적. 다음 세션 60kg 도전.", [
        {"name": "데드리프트", "type": "근력", "sets": 4, "reps": 8, "weight": 55},
        {"name": "루마니안 데드리프트", "type": "근력", "sets": 3, "reps": 10, "weight": 40},
        {"name": "플랭크", "type": "근력", "sets": 3, "reps": 3, "weight": 0},
        {"name": "코어 서킷", "type": "근력", "sets": 2, "reps": 12, "weight": 0},
    ]),
    ("14:00", "", None, "", 0, "공백", "", []),
    ("15:00", "박성호", "user-sungho", "1:1 PT", 60, "예정", "", [
        {"name": "벤치프레스", "type": "근력", "sets": 4, "reps": 8, "weight": 65},
        {"name": "인클라인 덤벨 프레스", "type": "근력", "sets": 3, "reps": 10, "weight": 26},
        {"name": "트라이셉스 딥", "type": "근력", "sets": 3, "reps": 12, "weight": 0},
    ]),
    # 상담으로 잡힌 가망 고객 — 로스터에 없으니 화면이 `이름(신규)` 로 부른다(#988).
    ("17:00", "윤가온", None, "상담", 30, "예정", "", []),
    ("19:00", "", None, "", 0, "공백", "", []),
]


def seed_member_health_data() -> None:
    db: Session = SessionLocal()
    try:
        valid = _valid_member_ids(db)
        for user_id, *_ in _MEMBERS:
            if user_id not in valid:
                # 계정/링크 없음(이메일 충돌 등) → FK 오류 방지 위해 건너뛴다.
                continue
            if user_id == load_fixture().user_app_seed_id:
                _seed_from_fixture(db, user_id)
            else:
                _seed_diet(db, user_id)
                _seed_history(db, user_id)
                _seed_exercise(db, user_id)
            _seed_chat(db, user_id)
            _seed_routines(db, user_id)
            _seed_health_profile(db, user_id)
        _seed_schedule(db, valid)
    finally:
        db.close()
    # 성별은 건강 프로필 행에 담기므로 **여기가 끝난 뒤** 채운다(#960). 먼저
    # 돌면 성별만 든 행이 생겨, 위쪽 `_seed_health_profile` 이 "이미 행이 있다"며
    # 위험도·영양 목표를 통째로 건너뛴다.
    from app.db.seed_trainer import seed_member_genders

    seed_member_genders()
    # 성별 시드가 만든 프로필 행에 시작 잔액을 넣으므로 그 뒤에 돈다.
    seed_demo_opening_points()


def seed_demo_opening_points() -> None:
    """데모 회원의 시작 포인트(`DEMO_OPENING_POINTS`, 25,000P)를 프로필에 넣는다(멱등).
    (#1786)

    예전에는 `/users/me/health` 가 위험 문구 없는 프로필에 1240 을 지어 보내,
    이지수·박성호 같은 데모 회원도 1240P 로 보였다. 이제 잔액을 프로필에서 그대로
    읽으므로 시작 잔액을 행에 넣어 둔다. 김민수는 건강 프로필 시드가 이미 넣는다.

    잔액이 0 이고 포인트 내역이 한 줄도 없는 회원만 채운다 — 적립·회수를 한 번이라도
    거친 잔액은 회원이 만든 값이라, 재기동마다 되돌리면 안 된다.
    """
    db: Session = SessionLocal()
    try:
        valid = _valid_member_ids(db)
        changed = False
        for user_id, *_ in _MEMBERS:
            if user_id not in valid:
                continue
            profile = db.scalar(
                select(models.HealthProfile).where(
                    models.HealthProfile.user_id == user_id
                )
            )
            if profile is None or (profile.activity_points or 0) != 0:
                continue
            has_history = db.scalar(
                select(models.PointsLedger.id)
                .where(models.PointsLedger.user_id == user_id)
                .limit(1)
            )
            if has_history is not None:
                continue
            profile.activity_points = points_service.DEMO_OPENING_POINTS
            changed = True
        if changed:
            _safe_commit(db)
    finally:
        db.close()


def ingest_seeded_documents() -> None:
    """시드가 **전부** 끝난 뒤 호출한다 — `init_db` 의 마지막 시드 단계.

    이 함수 안에서 부르면 안 된다. 확장 회원(4~15)의 기록은 `seed_roster_metrics`
    가 이 뒤에 만들기 때문에, 여기서 훑으면 첫 기동에 그들 문서가 통째로 빠진다
    (재기동해야 채워졌다 — 실제로 그렇게 나왔다).
    """
    db: Session = SessionLocal()
    try:
        _ingest_seeded_documents(db, _valid_member_ids(db))
    finally:
        db.close()


def _ingest_seeded_documents(db: Session, valid: set[str]) -> None:
    """시드 기록을 개인 RAG 문서로 적재한다(멱등) — #604.

    적재는 원래 실시간 API 경로에서만 일어난다. 시드는 테이블에 직접 insert 하므로
    데모 계정에는 개인 문서가 하나도 없었고, 그래서 비대칭이 생겼다:
      * 트레이너 루틴 생성 — `chat_messages` 를 직접 조회해 시드 대화를 본다
      * 회원 앱 AI 코치 — RAG 만 보므로 시드 식단·운동·대화를 못 본다
    데모에서 "이번 주 운동 어땠어?" 라고 물으면 기록이 있는데도 일반론이 나왔다.

    멱등은 `source_ref`(#603)로 판정한다 — 이미 적재된 기록은 임베딩을 다시 부르지
    않는다. 그래서 비용이 드는 것은 사실상 최초 기동 한 번뿐이다.
    """
    settings = get_settings()
    if not settings.seed_rag_ingest or not settings.rag_auto_ingest:
        return

    started = time.monotonic()
    ingested = 0
    for member_id in sorted(valid):
        ingested += _ingest_member_documents(db, member_id)

    if ingested:
        logger.info(
            "시드 개인 RAG 적재: %d건 (%.1fs). 이미 적재된 기록은 건너뜀.",
            ingested, time.monotonic() - started,
        )


#: 시드가 만든 행의 id 접두사. 이 접두사로만 좁히는 이유가 있다 — 사용자가 앱에서
#: 남긴 기록은 실시간 경로가 이미 적재했고, 그중 #603 이전에 적재된 문서는
#: `source_ref` 가 NULL 이라 멱등 판정에 걸리지 않는다. 전체를 훑으면 그런 기록이
#: 두 벌씩 검색된다.
_SEED_ID_PREFIX = "seed-"


def _ingest_member_documents(db: Session, member_id: str) -> int:
    """한 회원의 시드 식단·운동·대화를 적재하고 적재한 건수를 돌려준다."""
    count = 0

    for entry in db.scalars(
        select(models.DietEntry).where(
            models.DietEntry.user_id == member_id,
            models.DietEntry.id.like(f"{_SEED_ID_PREFIX}%"),
        )
    ).all():
        count += _ingested(
            personal_ingest.record_diet,
            db, member_id, date=entry.date, foods=_entry_foods(entry),
            total_calories=entry.total_calories, sodium_mg=entry.sodium_mg,
            sugar_g=entry.sugar_g, source_ref=entry.id,
        )

    for session in db.scalars(
        select(models.ExerciseSession).where(
            models.ExerciseSession.user_id == member_id,
            models.ExerciseSession.id.like(f"{_SEED_ID_PREFIX}%"),
        )
    ).all():
        count += _ingested(
            personal_ingest.record_exercise,
            db, member_id, date=_session_date(session),
            exercise_type=session.type, minutes=session.minutes,
            calories=session.calories, intensity=session.intensity,
            source_ref=session.id,
        )

    for msg in db.scalars(
        select(models.ChatMessage).where(
            models.ChatMessage.member_id == member_id,
            models.ChatMessage.id.like(f"{_SEED_ID_PREFIX}%"),
        )
    ).all():
        count += _ingested(
            personal_ingest.record_chat,
            db, member_id, sender=msg.sender, text=msg.body,
            date=clock.to_seoul(msg.created_at).date().isoformat(),
            source_ref=msg.id,
        )

    return count


def _ingested(record, db: Session, member_id: str, **fields) -> int:
    """`once` 경로로 적재하고 실제로 새로 넣었으면 1을 돌려준다.

    적재 여부를 여기서 미리 확인하지 않는다 — 확인과 삽입이 갈라지면 두 인스턴스가
    동시에 기동할 때 같은 기록의 청크가 두 벌 들어간다. `ensure_personal_text` 가
    잠금 안에서 확인까지 하므로, 우리는 문서 수 변화로 새로 넣었는지만 센다.
    """
    before = has_personal_doc(db, member_id, fields["source_ref"])
    record(db, member_id, once=True, **fields)
    return 0 if before else int(has_personal_doc(db, member_id, fields["source_ref"]))


def _entry_foods(entry: models.DietEntry) -> list[dict]:
    """저장된 foods_json → 리스트. 깨진 값이면 빈 목록(시드가 기동을 막으면 안 된다)."""
    try:
        value = json.loads(entry.foods_json or "[]")
    except (TypeError, ValueError):
        return []
    return value if isinstance(value, list) else []


def _session_date(session: models.ExerciseSession) -> str:
    """세션의 논리 운동일. 규칙은 [exercise_activity.activity_date_of] 하나다."""
    day = exercise_activity.activity_date_of(session)
    return day.isoformat() if day is not None else session.week_start


def _seed_schedule(db: Session, valid: set[str]) -> None:
    """트레이너 오늘 타임라인 시드(멱등, 날짜 인식). 트레이너 계정이 없으면 스킵."""
    if db.scalar(
        select(models.User.id).where(
            models.User.id == TRAINER_ID, models.User.role == "trainer"
        )
    ) is None:
        return
    today = clock.today_iso()
    # 오늘 스케줄이 이미 있으면 스킵(날짜 넘어가면 새로 시드)
    if db.scalar(
        select(models.TrainerSchedule.id)
        .where(
            models.TrainerSchedule.trainer_id == TRAINER_ID,
            models.TrainerSchedule.date == today,
        )
        .limit(1)
    ) is not None:
        return
    for i, (time, cname, mid, typ, dur, status, note, program) in enumerate(_SCHEDULE):
        member_id = mid if (mid and mid in valid) else None
        db.add(models.TrainerSchedule(
            id=f"seed-schedule-{today}-{i}",
            trainer_id=TRAINER_ID,
            member_id=member_id,
            date=today,
            time=time,
            client_name=cname,
            type=typ,
            duration_minutes=dur,
            status=status,
            note=note,
            program_json=json.dumps(program, ensure_ascii=False),
            sort_order=i,
        ))
    _safe_commit(db)


def _seed_chat(db: Session, member_id: str) -> None:
    """트레이너↔회원 채팅 스레드(멱등, 결정론적 id). 최근 시각으로 정렬되게 시드.

    **이미 있는 시드 행은 건너뛰지 않고 현재 대화로 덮어쓴다.** 건너뛰면, 전에
    시드된 DB(공유 Neon 포함)가 옛 본문을 그대로 들고 새로 늘어난 메시지만
    덧붙여 앞뒤가 다른 스레드가 된다 — 실제로 이 스레드는 다섯 개에서 열여덟
    개로 바뀌면서 앞 다섯 개의 본문도 전부 달라졌다(리뷰 지적). 대화가 줄어든
    경우를 위해 남는 시드 행도 지운다.

    회원이 앱에서 직접 보낸 메시지는 `chat-` 로 시작하는 다른 id 라 건드리지
    않는다 — 지우는 대상은 `seed-chat-{member_id}-` 접두사뿐이다.
    """
    thread = _CHAT.get(member_id)
    if not thread:
        return
    # 스레드가 최근으로 보이도록 base 를 하루 안쪽 과거로 두고, 메시지마다 그
    # 메시지의 days_ago 만큼 더 과거로 민다. 같은 날 안에서는 2분 간격이다.
    # days_ago 가 뒤로 갈수록 작아지므로 시각은 계속 증가한다 — 스레드 정렬은
    # (created_at, id) 이라 이 단조성이 대화 순서를 보장한다.
    #
    # **시각을 정오로 고정한다.** 예전에는 `now - 2시간` 을 그대로 썼는데, 시드가
    # 자정 근처(UTC 01:30~02:00)에 돌면 base 가 23:5x 가 되어 `+ i*2분` 이 자정을
    # 넘었다. 그러면 같은 days_ago 묶음이 이틀로 쪼개져 **사흘치 대화가 나흘**이 되고,
    # 날짜로 묶는 화면(하루치 AI 분석 안내)도 함께 어긋난다. CI 가 그 시간대에 걸리면
    # `test_demo_thread_spans_three_days` 가 아무 변경 없이 실패했다.
    #
    # 묶음 안의 최대 간격이 34분이라 정오 기준이면 어떤 시각에 시드해도 자정을 넘지
    # 않는다. 오늘 정오가 아직 오지 않았으면 하루 뒤로 물러 미래 시각을 만들지 않는다.
    now = datetime.now(timezone.utc)
    span = timedelta(minutes=(len(thread) - 1) * 2)
    base = now.replace(hour=12, minute=0, second=0, microsecond=0)
    if base + span > now:
        base -= timedelta(days=1)
    keep: set[str] = set()
    for i, (sender, text, days_ago) in enumerate(thread):
        cid = f"seed-chat-{member_id}-{i}"
        keep.add(cid)
        created_at = base - timedelta(days=days_ago) + timedelta(minutes=i * 2)
        sender_out = "member" if sender == "client" else "trainer"
        row = db.get(models.ChatMessage, cid)
        if row is None:
            db.add(models.ChatMessage(
                id=cid,
                trainer_id=TRAINER_ID,
                member_id=member_id,
                sender=sender_out,
                body=text,
                created_at=created_at,
            ))
            continue
        row.sender = sender_out
        row.body = text
        row.created_at = created_at

    stale = db.scalars(
        select(models.ChatMessage).where(
            models.ChatMessage.member_id == member_id,
            models.ChatMessage.id.like(f"seed-chat-{member_id}-%"),
        )
    ).all()
    for row in stale:
        if row.id not in keep:
            db.delete(row)
    _safe_commit(db)
    _seed_insight_memos(db, member_id, thread, base)


#: 시드 대화에서 감지 메모로 옮길 부위와, 그 부위를 불편하다고 말한 표현.
#: (#1655) 트레이너 웹의 `ChatContextInsightDetector` 가 배너를 띄우는 것과 같은
#: 문장을 고르기 위한 **시드 전용** 축약본이다 — 감지 자체는 앱이 하고, 여기서는
#: 데모 계정이 처음부터 화면과 같은 메모를 갖고 있게 하는 것이 목적이다.
_INSIGHT_BODY_PARTS = ("무릎", "허리", "어깨", "발목", "손목", "목")
_INSIGHT_DISCOMFORT = ("아프", "아파", "불편", "시큰", "당기", "결리", "뻐근", "쑤시")

#: 감지 메모를 심는 창(일). 프로그램 탭 분석 박스가 읽는 창과 같다.
_INSIGHT_MEMO_DAYS = 7


def _seed_insight_memos(
    db: Session,
    member_id: str,
    thread: list[tuple[str, str, int]],
    base: datetime,
) -> None:
    """시드 대화의 불편 호소를 채팅 감지 메모로 남긴다(멱등). (#1655)

    데모 계정이 실 API 로 프로그램 탭을 열었을 때, 트레이너 웹 로컬 데모와 같은
    `최근 7일 AI 감지 메모` 를 보게 하려는 것이다. `insight_id` 는 앱이 만드는
    값(`"{메시지 id}:discomfort"`)과 같은 규칙이라, 데모에서 그 배너의
    `메모에 추가` 를 눌러도 메모가 두 번 쌓이지 않고 `메모 추가됨` 으로 뜬다.

    본문은 앱이 저장하는 요약과 같은 문구(`"무릎 불편 감지"`)다.
    """
    for i, (sender, text, days_ago) in enumerate(thread):
        if sender != "client" or days_ago >= _INSIGHT_MEMO_DAYS:
            continue
        if not any(word in text for word in _INSIGHT_DISCOMFORT):
            continue
        part = next((p for p in _INSIGHT_BODY_PARTS if p in text), None)
        if part is None:
            continue
        insight_id = f"seed-chat-{member_id}-{i}:discomfort"
        memo_id = f"seed-memo-{member_id}-{i}"
        created_at = base - timedelta(days=days_ago) + timedelta(minutes=i * 2)
        row = db.get(models.TrainerClientMemo, memo_id)
        if row is None:
            db.add(models.TrainerClientMemo(
                id=memo_id,
                trainer_id=TRAINER_ID,
                member_id=member_id,
                body=f"{part} 불편 감지",
                source="chat_insight",
                insight_id=insight_id,
                insight_kind="discomfort",
                created_at=created_at,
            ))
            continue
        # 대화가 바뀌면 메모도 따라간다 — 시드 행은 늘 지금 대화의 것이다.
        row.body = f"{part} 불편 감지"
        row.insight_id = insight_id
        row.created_at = created_at
    _safe_commit(db)


def _routine_rows(member_id: str) -> list[FixtureRoutine]:
    """이 회원에게 시드할 개인운동. 김민수는 픽스처가 단일 원본이다. (#1199)

    픽스처는 네 줄 중 둘을 트레이너가 보낸 것으로 둔다. 시드가 표를 따로 들고
    있던 동안은 그 넷이 전부 `ai` 로 들어가, 목업에서는 갈라 보이던 출처가
    실서버에서는 한 줄로 뭉쳤다. id 규칙(`seed-routine-{회원}-{순번}`)은 양쪽이
    같아서 이미 시드된 DB 의 행과 그대로 이어진다.
    """
    fixture = load_fixture()
    if member_id == fixture.user_app_seed_id:
        return list(fixture.routines)
    return [
        FixtureRoutine(
            id=f"seed-routine-{member_id}-{i}",
            name=name,
            minutes=minutes,
            type=rtype,
            reason=reason,
            # 픽스처가 없는 회원은 예전과 같이 전부 AI 추천이다.
            source="ai",
            sets=sets,
            reps=reps,
            weight=weight,
        )
        for i, (name, minutes, rtype, reason, sets, reps, weight) in enumerate(
            _ROUTINES.get(member_id, ())
        )
    ]


_T = TypeVar("_T")


def _strength_only(type_: str, value: _T | None) -> _T | None:
    """근력이 아니면 버린다 — 세트·횟수·중량은 근력에서만 뜻이 있다(#1276)."""
    return value if type_ == "근력" else None


def _seed_routines(db: Session, member_id: str) -> None:
    """개인운동 시드(멱등, 결정론적 id).

    이미 있는 시드 행은 픽스처가 적은 내용으로 맞춘다 — 픽스처를 고쳐도 한 번
    시드된 DB 가 옛 값을 그대로 들고 있으면, 실연동 데모가 목업과 다른 화면을
    보여 준다. 트레이너·회원이 만든 행은 id 접두사가 달라 여기 걸리지 않고,
    검토 상태(`status`)처럼 시드가 소유하지 않는 값은 건드리지 않는다.
    """
    routines = _routine_rows(member_id)
    if not routines:
        return
    for i, routine in enumerate(routines):
        row = db.get(models.TrainerRoutine, routine.id)
        if row is None:
            db.add(models.TrainerRoutine(
                id=routine.id,
                trainer_id=TRAINER_ID,
                member_id=member_id,
                name=routine.name,
                minutes=routine.minutes,
                type=routine.type,
                reason=routine.reason,
                source=routine.source,
                # 근력에만 싣는다 — 배정 API(`assign_routine`)와 같은 규칙이라,
                # 시드로 들어온 배정과 트레이너가 보낸 배정이 화면에서 같은
                # 모양으로 읽힌다(#1276).
                sets=_strength_only(routine.type, routine.sets),
                reps=_strength_only(routine.type, routine.reps),
                weight=_strength_only(routine.type, routine.weight),
                sort_order=i,
            ))
            continue
        row.name = routine.name
        row.minutes = routine.minutes
        row.type = routine.type
        row.reason = routine.reason
        row.source = routine.source
        row.sets = _strength_only(routine.type, routine.sets)
        row.reps = _strength_only(routine.type, routine.reps)
        row.weight = _strength_only(routine.type, routine.weight)
        row.sort_order = i
    _safe_commit(db)


#: 픽스처가 소유한 행의 id 접두사. `seed-` 로 시작하므로 기존의 "시드 행만 훑는다"
#: 규칙(RAG 적재·사용자 데이터 보존)에 그대로 걸리고, 예전 시드가 만든 행과는
#: 구별된다 — 그래야 이미 돌던 DB 에서 옛 행을 지우고 픽스처로 갈아끼울 수 있다.
_FIXTURE_ID_PREFIX = "seed-fix-"


@dataclass(frozen=True)
class _TypeTotals:
    """하루·한 종류로 접은 값. 운동 기록 한 행이 되는 그대로다."""

    minutes: int
    calories: int
    name: str
    #: 근력이면 그날 한 세트 수의 **합**. 다른 유형은 None 이다.
    sets: int | None = None
    #: 근력이면 그날 한 횟수 중 가장 많은 수. 세트와 달리 더하지 않는다 — 한
    #: 세트당 수라 합계는 아무도 한 적 없는 값이 된다(#1310 의 PT 파생 기록과
    #: 같은 규칙).
    reps: int | None = None


def _by_type(
    exercises: tuple[FixtureExercise, ...],
) -> dict[str, _TypeTotals]:
    """운동을 종류별로 합친다. 픽스처 순서를 유지한다.

    종류는 표준 어휘로 접어서 센다 (#996). 픽스처가 아직 옛 이름을 쓰더라도
    DB 에는 표준 값만 들어가야 앱이 유형을 다시 매핑하지 않는다.

    이름도 함께 잇는다 — 리포트의 요일 칸이 그날 무엇을 했는지를 운동 기록의
    이름으로 적기 때문이다(#1288). 종류로 합치면서 이름까지 버리면 데모의 요일
    칸이 "유산소 · 근력" 두 줄로만 남는다. PT 완료가 만드는 기록도 여러 운동을
    쉼표로 잇는 같은 규칙을 쓴다.

    세트·횟수도 함께 접는다 (#1265). 예전에는 픽스처가 적어 둔 세트를 버려서,
    화면이 분에서 세트를 되짚었다 — 같은 회원의 같은 날 근력이 앱마다 다른 수로
    보였다.
    """
    totals: dict[str, _TypeTotals] = {}
    for exercise in exercises:
        kind = exercise_types.normalize(exercise.type)
        prev = totals.get(kind)
        strength = kind == exercise_types.STRENGTH
        totals[kind] = _TypeTotals(
            minutes=(prev.minutes if prev else 0) + exercise.minutes,
            calories=(prev.calories if prev else 0) + exercise.calories,
            name=(
                f"{prev.name}, {exercise.name}"
                if prev and prev.name
                else exercise.name
            ),
            sets=(
                _add(prev.sets if prev else None, exercise.sets)
                if strength
                else None
            ),
            reps=(
                _peak(prev.reps if prev else None, exercise.reps)
                if strength
                else None
            ),
        )
    return totals


def _add(left: int | None, right: int | None) -> int | None:
    """둘 다 없으면 None. 하나만 있으면 그 값 — 0 으로 채우지 않는다.

    0 은 "0세트를 했다" 가 되고, None 은 "적지 않았다" 다. 그래프가 둘을 다르게
    읽는다.
    """
    if left is None:
        return right
    if right is None:
        return left
    return left + right


def _peak(left: int | None, right: int | None) -> int | None:
    if left is None:
        return right
    if right is None:
        return left
    return max(left, right)


def _seed_from_fixture(db: Session, member_id: str) -> None:
    """픽스처 회원(김민수)의 식단·운동기록·운동세션을 픽스처 그대로 깐다.

    다른 회원과 달리 **다시 깐다**. 픽스처는 "오늘로부터 며칠 전"으로 적혀 있어서
    날짜가 넘어가면 모든 날이 하루씩 앞으로 미끄러져야 하는데, 있는 날을 건너뛰는
    방식으로는 예전 값이 그 자리에 남아 사용자 앱과 어긋난다. 사용자 앱 시드도
    같은 규칙으로 움직인다.

    지우는 것은 `seed-` 로 시작하는 행뿐이다 — 회원이 앱에서 직접 남긴 기록은 다른
    id 를 갖고 그대로 살아남는다.
    """
    fixture = load_fixture()
    today = clock.today()
    days = fixture.days_for(today)

    # 이 회원의 행 id 는 픽스처와 오늘 날짜만으로 정해진다 — 넣기 전에도 알 수 있다.
    kept_refs = _fixture_row_ids(member_id, days)

    # 문지기보다 **먼저** 쓸어낸다. 뒤에 두면, 이미 픽스처로 한 번 깔린 DB 는 문지기에
    # 걸려 되돌아가므로 예전 행을 가리키던 문서가 영영 남는다.
    _drop_orphaned_personal_docs(db, member_id, kept_refs)

    # 오늘치가 이미 픽스처로 깔려 있으면 여기서 끝낸다. 기동마다 수백 행을 지웠다
    # 넣는 것을 막는 문지기다.
    #
    # 접두사가 `seed-fix-` 인 이유: 예전 시드도 오늘 3끼를 `seed-diet-{회원}-{날짜}-0`
    # 으로 넣었다. 그 id 를 문지기로 삼으면 이미 돌던 DB 에서는 옛 행이 문지기에
    # 걸려 픽스처가 영영 깔리지 않는다 — 실제로 그렇게 나왔다.
    marker = f"{_FIXTURE_ID_PREFIX}diet-{member_id}-{today.isoformat()}-0"
    if db.scalar(
        select(models.DietEntry.id).where(models.DietEntry.id == marker).limit(1)
    ) is not None:
        _safe_commit(db)
        return

    for model in (models.DietEntry, models.ExerciseSession):
        db.query(model).filter(
            model.user_id == member_id, model.id.like("seed-%")
        ).delete(synchronize_session=False)
    db.query(models.RoutineHistory).filter(
        models.RoutineHistory.member_id == member_id,
        models.RoutineHistory.id.like("seed-%"),
    ).delete(synchronize_session=False)

    for day in days:
        # 행 id 는 **날짜에서 만든다**. 픽스처가 시연용으로 못 박아 둔 id 는 사용자
        # 앱의 로컬 DB 것이다 — 백엔드는 과거를 지우지 않고 쌓아 두므로 날짜가
        # 없는 id 를 쓰면 다음 날 같은 id 로 부딪힌다.
        for index, meal in enumerate(day.meals):
            db.add(models.DietEntry(
                id=f"{_FIXTURE_ID_PREFIX}diet-{member_id}-{day.iso}-{index}",
                user_id=member_id,
                date=day.iso,
                meal_type=meal.meal_type,
                time_label=meal.time_label,
                foods_json=meal.foods_json(),
                total_calories=meal.calories,
                carbs_g=meal.carbs_g,
                protein_g=meal.protein_g,
                fat_g=meal.fat_g,
                sodium_mg=meal.sodium_mg,
                sugar_g=meal.sugar_g,
                engine="seed",
            ))

        if not day.exercises:
            continue  # 휴식일. 이력에도 세션에도 남기지 않는다.

        db.add(models.RoutineHistory(
            id=f"{_FIXTURE_ID_PREFIX}hist-{member_id}-{day.iso}",
            member_id=member_id,
            trainer_id=TRAINER_ID if day.is_pt else None,
            date=day.iso,
            kind_label=day.routine_label,
            completion_rate=day.completion,
            exercises_json=json.dumps(
                [e.label for e in day.exercises], ensure_ascii=False
            ),
            client_feedback=day.client_feedback,
            trainer_note=day.trainer_note,
        ))

        # 세션은 **실제로 한** 운동만 쌓는다. 못 한 항목까지 넣으면 이행률은 67% 인데
        # 주간 운동 시간은 100% 인 날이 나온다.
        #
        # 하루에 같은 종류가 둘일 수 있어(PT 날의 레그프레스·레그컬은 둘 다 근력)
        # 종류로 합친다. 주간 활동 그래프가 하루·종류당 한 칸을 그리므로 나눠 넣을
        # 자리도 없다.
        for kind, totals in _by_type(day.done_exercises).items():
            db.add(models.ExerciseSession(
                id=f"{_FIXTURE_ID_PREFIX}ex-{member_id}-{day.iso}-{kind}",
                user_id=member_id,
                week_start=day.week_start,
                day_label=day.day_label,
                type=kind,
                name=totals.name,
                minutes=totals.minutes,
                calories=totals.calories,
                # 픽스처가 적어 둔 세트·횟수를 그대로 남긴다 — 없으면 화면이
                # 분에서 세트를 되짚어 아무도 적은 적 없는 수를 그린다. (#1265)
                sets=totals.sets,
                reps=totals.reps,
                intensity="moderate",
                # 실제로 운동한 날의 시각을 함께 적는다 (#1264). `created_at` 은
                # 재시드 시각이라, 이것이 없으면 35주 전 운동도 방금 만든 행으로
                # 남아 최근 활동 판단이 어긋난다.
                completed_at=exercise_activity.noon(day.day),
            ))

    _safe_commit(db)


def _fixture_row_ids(member_id: str, days: list) -> set[str]:
    """픽스처가 이 회원에게 넣을 식단·운동 행 id 전부.

    삽입과 **같은 규칙**으로 만든다 — 한쪽만 고치면 멀쩡한 문서가 고아로 몰려
    지워진다. 개인 RAG 문서 정리(`_drop_orphaned_personal_docs`)가 이 집합을 쓴다.
    """
    ids: set[str] = set()
    for day in days:
        for index in range(len(day.meals)):
            ids.add(f"{_FIXTURE_ID_PREFIX}diet-{member_id}-{day.iso}-{index}")
        for kind in _by_type(day.done_exercises):
            ids.add(f"{_FIXTURE_ID_PREFIX}ex-{member_id}-{day.iso}-{kind}")
    return ids


def _drop_orphaned_personal_docs(
    db: Session, member_id: str, kept_refs: set[str]
) -> None:
    """지워진 시드 행을 가리키는 개인 RAG 문서를 함께 지운다.

    개인 문서는 행 id(`source_ref`)로 그 기록을 가리킨다. 픽스처를 다시 깔면서 행을
    지우면 문서만 남는데, 적재는 **추가만** 하므로 그 문서는 영영 남아 **옛 수치를
    말한다** — 코치가 같은 날짜에 대해 새 값과 옛 값을 함께 인용하게 된다.

    식단·운동 문서만 대상이다. 대화(`seed-chat-…`)는 이 함수가 건드리는 행이
    아니므로 그대로 둔다.
    """
    stale = db.query(models.CoachDocument).filter(
        models.CoachDocument.user_id == member_id,
        or_(
            models.CoachDocument.source_ref.like("seed-diet-%"),
            models.CoachDocument.source_ref.like("seed-ex-%"),
            models.CoachDocument.source_ref.like(f"{_FIXTURE_ID_PREFIX}diet-%"),
            models.CoachDocument.source_ref.like(f"{_FIXTURE_ID_PREFIX}ex-%"),
        ),
        models.CoachDocument.source_ref.notin_(kept_refs or {""}),
    )
    removed = stale.delete(synchronize_session=False)
    if removed:
        logger.info(
            "dropped %s stale personal docs for %s (fixture reseed)",
            removed,
            member_id,
        )


def _has_diet_on(db: Session, member_id: str, day: str) -> bool:
    return db.scalar(
        select(models.DietEntry.id)
        .where(models.DietEntry.user_id == member_id, models.DietEntry.date == day)
        .limit(1)
    ) is not None


def _seed_diet(db: Session, member_id: str) -> None:
    meals = _TODAY_MEALS.get(member_id)
    sodium_week = _SODIUM_WEEK.get(member_id)
    if not meals or not sodium_week:
        return

    today = clock.today()
    today_str = today.isoformat()

    # 오늘 3끼 (오늘 기록이 아직 없을 때만)
    if not _has_diet_on(db, member_id, today_str):
        for i, meal in enumerate(meals):
            meal_type, items, cal, na, sugar, carbs, protein, fat = meal
            db.add(models.DietEntry(
                id=f"seed-diet-{member_id}-{today_str}-{i}",
                user_id=member_id,
                date=today_str,
                meal_type=meal_type,
                time_label={"breakfast": "08:00", "lunch": "12:30", "dinner": "19:00"}.get(meal_type, ""),
                foods_json=json.dumps(
                    [{"name": items, "calories": cal, "sodium_mg": na, "sugar_g": sugar}],
                    ensure_ascii=False,
                ),
                total_calories=cal,
                carbs_g=carbs,
                protein_g=protein,
                fat_g=fat,
                sodium_mg=na,
                sugar_g=sugar,
                engine="seed",
            ))

    # 과거 일별 기록 (해당 날짜에 기록이 없을 때만 — 중복 합산 방지).
    # 리포트가 과거 주로 이동할 수 있어 이번 주만 채우면 한 주만 뒤로 가도
    # 화면이 빈다(#752).
    # 이미 기록이 있는 날짜를 한 번에 읽는다 — 날마다 조회하면 12주치 시딩이
    # 눈에 띄게 느려진다.
    logged = set(
        db.scalars(
            select(models.DietEntry.date).where(
                models.DietEntry.user_id == member_id
            )
        ).all()
    )
    for offset in range(1, _HISTORY_WEEKS * 7):
        d = (today - timedelta(days=offset)).isoformat()
        if d in logged:
            continue
        logged.add(d)
        idx = (offset // 7) % len(_SODIUM_FACTORS)
        weekday = (today - timedelta(days=offset)).weekday()
        if offset == 1:
            na, calories, sugar = _FEAST_SODIUM_MG, _FEAST_KCAL, _FEAST_SUGAR_G
        else:
            na = round(sodium_week[6 - (offset % 7)] * _SODIUM_FACTORS[idx])
            calories = round(_WEEKDAY_KCAL[weekday] * _CALORIE_FACTORS[idx])
            sugar = round(_WEEKDAY_SUGAR[weekday] * _SUGAR_FACTORS[idx], 1)
        db.add(models.DietEntry(
            id=f"seed-diet-{member_id}-{d}-agg",
            user_id=member_id,
            date=d,
            meal_type="lunch",
            time_label="",
            foods_json=json.dumps(
                [{"name": "기록된 식단", "calories": calories, "sodium_mg": na, "sugar_g": sugar}],
                ensure_ascii=False,
            ),
            total_calories=calories,
            sodium_mg=na,
            sugar_g=sugar,
            engine="seed",
        ))
    _safe_commit(db)


def _seed_history(db: Session, member_id: str) -> None:
    sessions = _HISTORY.get(member_id)
    if not sessions:
        return

    today = clock.today()
    # 오늘/이틀전/나흘전을 한 주기로 두고 과거 주까지 되풀이한다. 리포트가
    # 과거 주로 이동할 수 있어, 이번 주만 채우면 이행률이 곧 비어 버린다(#752).
    #
    # 멱등성은 행 id(회원+날짜)로 지킨다. 예전처럼 "오늘 기록이 있으면 통째로
    # 건너뛰기" 로 두면, 오늘치가 이미 있는 DB 에는 과거 주가 영영 채워지지
    # 않는다.
    existing = set(
        db.scalars(
            select(models.RoutineHistory.id).where(
                models.RoutineHistory.member_id == member_id
            )
        ).all()
    )
    for week in range(_HISTORY_WEEKS):
        factor = _COMPLETION_FACTORS[week % len(_COMPLETION_FACTORS)]
        for idx, (rate, kind, exercises, feedback, note) in enumerate(sessions):
            d = (today - timedelta(days=idx * 2 + week * 7)).isoformat()
            hid = f"seed-hist-{member_id}-{d}"
            if hid in existing:
                continue
            existing.add(hid)
            db.add(models.RoutineHistory(
                id=hid,
                member_id=member_id,
                trainer_id=TRAINER_ID if kind.startswith("PT") else None,
                date=d,
                kind_label=kind,
                completion_rate=min(100, round(rate * factor)),
                exercises_json=json.dumps(exercises, ensure_ascii=False),
                # 과거 주까지 같은 문구를 반복하면 화면이 복사본처럼 읽힌다 —
                # 이번 주 것만 실제 대화를 남긴다.
                client_feedback=feedback if week == 0 else "",
                trainer_note=note if week == 0 else "",
            ))
    _safe_commit(db)


def _seed_exercise(db: Session, member_id: str) -> None:
    """회원 이번 주 운동 세션 시드(멱등, 날짜 인식) — 사용자 앱 운동 화면용.

    이번 주 세션 중 **오늘까지의 요일만** 넣는다. 주중에 실행돼도 미래 요일이 이번 주
    합계·streak 에 잡히지 않도록(예: 수요일에 시드해도 목~일은 넣지 않음). 멱등은
    세션 id 단위로 판정하므로, 주가 진행되며 재실행되면 새로 지난 요일이 채워지고
    이미 있는 요일은 건너뛴다(중복·왜곡 없음). 주가 바뀌면 새 week_start 로 누적된다."""
    week = _EXERCISE_WEEK.get(member_id)
    if not week:
        return
    today = clock.today()
    week_start = (today - timedelta(days=today.weekday())).isoformat()  # 이번 주 월요일
    added = False
    for day_label, ex_type, minutes, calories in week:
        idx = _WEEKDAY_INDEX.get(day_label)
        if idx is None or idx > today.weekday():
            continue  # 미래(또는 알 수 없는) 요일은 아직 시드하지 않는다.
        session_id = f"seed-ex-{member_id}-{week_start}-{day_label}"
        if db.scalar(
            select(models.ExerciseSession.id)
            .where(models.ExerciseSession.id == session_id)
            .limit(1)
        ) is not None:
            continue  # 멱등: 이미 있는 요일은 스킵.
        db.add(models.ExerciseSession(
            id=session_id,
            user_id=member_id,
            week_start=week_start,
            day_label=day_label,
            type=exercise_types.normalize(ex_type),
            minutes=minutes,
            calories=calories,
            intensity="moderate",
            # 그 요일의 시각을 함께 적는다 — 세 날짜 필드가 같은 날을 가리켜야
            # 시드 시각(`created_at`)이 최근 활동 판단에 새지 않는다. (#1264)
            completed_at=exercise_activity.noon(
                today - timedelta(days=today.weekday() - idx)
            ),
        ))
        added = True
    if added:
        _safe_commit(db)


def _seed_health_profile(db: Session, member_id: str) -> None:
    """회원 건강 프로필(위험도·활동점수·기본정보) 시드(멱등). 이미 있으면 스킵.
    사용자 앱 홈/My Health 의 위험 카드·활동점수가 실데이터로 뜨게 한다."""
    fields = _HEALTH_PROFILE.get(member_id)
    if not fields:
        return
    existing = db.scalar(
        select(models.HealthProfile)
        .where(models.HealthProfile.user_id == member_id)
        .limit(1)
    )
    if existing is not None:
        # 이미 시드된 데모 DB 는 옛 질환 이름(고혈압·당뇨 전단계)을 들고 있다. 옛
        # 시드 값 그대로면 새 목표로 바꾸고, 회원이 고친 값이면 옛 이름만 정리한다(#1814).
        if existing.conditions == _LEGACY_DEMO_CONDITIONS:
            updated = fields["conditions"]
        else:
            updated = normalize_conditions(existing.conditions) or ""
        if updated != existing.conditions:
            existing.conditions = updated
            _safe_commit(db)
        return
    db.add(models.HealthProfile(user_id=member_id, **fields))
    _safe_commit(db)
