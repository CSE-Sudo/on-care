"""담당 회원의 지난 4주 끼니·운동 세션 시드. (#2729)

`seed_roster`·`seed_member_data` 는 김민수를 뺀 회원의 지난 날을 **하루 한 줄**
(`기록된 식사`·`기록된 식단`)로만 남긴다 — 로스터·리포트 지표를 만들 최소 기록이다.
그래서 실서버 데모 계정에서 회원 상세의 지난 날짜를 펼치면 끼니 카드가 한 줄뿐이고,
운동 현황에는 유형별 막대·`N일 연속` 이 없고, 식단 분석·AI 식단 추천의 근거가 빈다.

여기서는 최근 [LOG_DAYS] 일의 그 한 줄을 **같은 합계의 끼니 여럿**으로 나눈다.
트레이너 웹 데모(#2667, `frontend/flutter_trainer/lib/core/storage/seed_data.dart` 의
`_mealsOf`)와 같은 규칙이다 — 합계를 나누므로 리포트·로스터 지표는 그대로다.

운동 세션은 여기서 만들지 않는다(#3003). 예전에는 그날 루틴 기록에서 요일 루틴을
`member` 로 심어, 같은 날 개인운동·PT 와 다른 운동이 `직접 기록한 운동` 에 섰다.
개인운동 완료는 `seed_roster`·`seed_member_data` 가, 회원이 직접 적은 운동은
`seed_workouts.MEMBER_LOGS` 가 정한다. 이미 깔린 그 행은 지운다([_drop_routine_sessions]).

멱등: 나눈 끼니(`seed-meal-…`)가 있는 날은 건너뛴다. 회원이 직접 남긴 기록(한 줄
시드가 아닌 행)이 있는 날은 건드리지 않는다.
"""
from __future__ import annotations

import json
import logging
import re
from datetime import date, timedelta

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core import clock
from app.db.session import SessionLocal
from app.models import models

logger = logging.getLogger(__name__)

_PG_UNIQUE_VIOLATION = "23505"

#: 끼니·운동을 심는 날 수(오늘 포함). 식단 분석·AI 식단 추천이 읽는 창(28일)과 같다.
LOG_DAYS = 28

#: 나눈 끼니의 id 머리. 이 머리가 있는 날은 이미 나눈 날이다.
MEAL_ID_PREFIX = "seed-meal-"

#: 운동 세션 id 머리.
SESSION_ID_PREFIX = "seed-log-ex-"

#: 시드 문구에서 바뀐 표기 — (옛 표기 정규식, 지금 표기). 이미 시드된 DB 의 시드
#: 행이 옛 표기를 그대로 들고 있지 않게, 시드가 다시 돌 때 갈아 끼운다(#3201).
#: `런닝머신` 은 운동 카탈로그의 별칭이라 그대로 둔다.
_RENAMED_SEED_TERMS: tuple[tuple[re.Pattern[str], str], ...] = (
    (re.compile(r"런닝(?!머신)"), "러닝"),
)


def current_seed_text(text: str | None) -> str | None:
    """시드가 만든 문구를 지금 시드 표기로 고친다 — 바뀐 표기가 없으면 그대로."""
    if not text:
        return text
    for pattern, replacement in _RENAMED_SEED_TERMS:
        text = pattern.sub(replacement, text)
    return text


#: 시드 문장에서 바뀐 것 — 옛 문장 → 지금 문장(#3201·#3202). 낱말 치환으로는 못
#: 고치는 표기다: `수업`·`세션` 은 일반 낱말이고 `PT 세션 · 트레이너 지도` 같은
#: 데이터 값에도 들어 있어, 시드가 넣은 문장과 **통째로 같을 때만** 바꾼다.
#: 트레이너가 고쳐 쓴 문장은 표에 없으니 그대로 남는다.
_RENAMED_SEED_SENTENCES: dict[str, str] = {
    # 트레이너 할 일(`seed_trainer_notes._FOLLOW_UPS`).
    "노쇼 반복 — 수업 시간대 재조정 제안": "노쇼 반복 — PT 시간대 재조정 제안",
    # 지난 PT 메모(`seed_trainer_notes._PAST_PT_NOTES`).
    "3주 만의 수업. 체력 저하가 커서 강도를 70%로 낮춰 진행.":
        "3주 만의 PT. 체력 저하가 커서 강도를 70%로 낮춰 진행.",
    "첫 수업. 기구 사용법 위주로 안내, 스쿼트 자세 좋음.":
        "첫 PT. 기구 사용법 위주로 안내, 스쿼트 자세 좋음.",
    "당일 취소 후 보강 수업. 컨디션 좋음.": "당일 취소 후 보강 PT. 컨디션 좋음.",
    "수업 시간대 바꾸고 싶다고 함. 상담 잡기로.": "PT 시간대 바꾸고 싶다고 함. 상담 잡기로.",
    # 김민수 픽스처 PT 메모(`demo_fixture_data.json` 의 `trainerNote`).
    "무릎 가동범위 체크 필요. 다음 세션 중량 조절 예정.":
        "무릎 가동범위 체크 필요. 다음 PT 중량 조절 예정.",
    "첫 세션. 체력 수준 점검 위주로 가볍게 진행.": "첫 PT. 체력 수준 점검 위주로 가볍게 진행.",
    "벤치프레스 35kg 4×10 안정. 다음 세션도 같은 무게로 반복.":
        "벤치프레스 35kg 4×10 안정. 다음 PT도 같은 무게로 반복.",
    "하체 근력 향상 확인. 다음 세션 레그프레스 5kg 증량.":
        "하체 근력 향상 확인. 다음 PT 레그프레스 5kg 증량.",
    "벤치프레스 37.5kg 4×10 성공. 다음 세션 40kg.": "벤치프레스 37.5kg 4×10 성공. 다음 PT 40kg.",
    # 오늘 타임라인 이지수 PT 메모(`seed_member_data._SCHEDULE`).
    "데드리프트 자세 안정적. 다음 세션 60kg 도전.": "데드리프트 자세 안정적. 다음 PT 60kg 도전.",
}


def current_seed_sentence(text: str | None) -> str | None:
    """시드가 넣은 문장이 옛 문장과 정확히 같으면 지금 문장으로 — 아니면 그대로."""
    if not text:
        return text
    return _RENAMED_SEED_SENTENCES.get(text, text)

#: 회원 → 트레이너 웹 데모의 회원 번호(`seed-client-N`). 루틴을 돌려 고르는 씨앗이라
#: 데모와 같은 날 같은 운동이 나온다.
_MEMBER_NO: dict[str, int] = {
    "user-jisu": 2,
    "user-sungho": 3,
    "user-hayun": 4,
    "user-woojin": 5,
    "user-kangseoyeon": 6,
    "user-dohyun": 7,
    "user-sera": 8,
    "user-junhyuk": 9,
    "user-yuna": 10,
    "user-jiho": 11,
    "user-gayoung": 12,
    "user-taekyung": 13,
    "user-seojin": 14,
    "user-eunchae": 15,
}

#: 끼니 수 → 그날 끼니 자리(먹은 순서)와 시각.
_MEAL_SLOTS: tuple[tuple[tuple[str, str], ...], ...] = (
    (("lunch", "12:30"),),
    (("lunch", "12:30"), ("dinner", "19:00")),
    (("breakfast", "08:00"), ("lunch", "12:30"), ("dinner", "19:00")),
    (
        ("breakfast", "08:00"), ("lunch", "12:30"),
        ("snack", "15:30"), ("dinner", "19:00"),
    ),
)

#: 끼니 본보기 — (이름, kcal, 나트륨 mg, 당류 g, 먹은 양 g). 트레이너 웹 데모 로스터의
#: 오늘 끼니를 모은 것이다(`_mealTemplates`). 새 음식을 지어내지 않는다.
_MEAL_TEMPLATES: dict[str, tuple[tuple[tuple[str, int, int, float, int], ...], ...]] = {
    "breakfast": (
        (("그릭요거트", 180, 190, 6.0, 150), ("블루베리", 100, 10, 9.0, 150),),
        (("삶은 계란 3개", 230, 210, 1.0, 150), ("잼 토스트", 250, 310, 12.0, 80),),
        (("통밀토스트", 190, 270, 3.0, 70), ("아보카도", 150, 20, 0.5, 100),),
        (("오트밀", 260, 160, 1.0, 70), ("바나나", 110, 0, 6.0, 120), ("견과", 150, 30, 1.0, 25),),
        (("편의점 삼각김밥 2개", 420, 780, 6.0, 220),),
        (("아메리카노", 20, 10, 0.0, 355),),
        (("두유", 130, 110, 8.0, 190), ("삶은 계란 2개", 130, 130, 0.5, 100),),
        (("시리얼", 250, 220, 15.0, 60), ("우유", 130, 100, 10.0, 200),),
        (("토스트", 240, 300, 9.0, 80), ("커피", 50, 10, 5.0, 250),),
        (("계란 5개", 390, 340, 1.5, 250), ("오트밀", 330, 140, 1.5, 90),),
        (("북엇국", 220, 1110, 2.0, 400), ("공기밥", 300, 10, 0.0, 210),),
        (("바나나", 100, 10, 5.0, 110), ("우유", 120, 120, 4.0, 200),),
    ),
    "lunch": (
        (("현미밥", 310, 5, 0.5, 210), ("불고기", 330, 720, 9.0, 150), ("시금치나물", 110, 255, 1.5, 70),),
        (("짜장면", 890, 1200, 26.0, 650),),
        (("닭가슴살 도시락", 520, 640, 9.5, 380),),
        (("현미밥", 330, 10, 0.5, 220), ("흰살생선", 300, 340, 0.0, 200), ("나물", 150, 250, 0.5, 120),),
        (("마라탕", 980, 1850, 18.0, 700),),
        (("부대찌개", 620, 1640, 9.0, 600), ("공기밥", 300, 10, 0.0, 210),),
        (("김치찌개", 480, 1410, 7.0, 500), ("공기밥", 300, 10, 0.0, 210),),
        (("비빔밥 (고추장 절반)", 680, 780, 14.0, 450),),
        (("백반 정식", 720, 980, 21.0, 550),),
        (("샌드위치", 480, 720, 15.0, 220),),
        (("소고기 덮밥", 780, 700, 14.0, 450), ("현미밥 곱빼기", 400, 20, 1.0, 270),),
        (("칼국수", 790, 980, 5.0, 700), ("겉절이", 90, 280, 9.0, 80),),
        (("샐러드 볼", 430, 610, 5.0, 350),),
    ),
    "dinner": (
        (("연어 샐러드", 650, 620, 12.0, 350),),
        (("삼겹살", 590, 260, 0.5, 180), ("쌈채소", 40, 20, 2.5, 100), ("쌈장", 100, 400, 13.0, 40),),
        (("채소 스프", 150, 480, 14.0, 300), ("두부", 220, 230, 4.5, 250), ("현미밥", 290, 10, 0.5, 200),),
        (("닭가슴살", 230, 150, 0.0, 150), ("고구마", 170, 30, 4.0, 130), ("파스타", 500, 380, 3.0, 350),),
        (("치킨", 960, 870, 48.0, 400), ("맥주", 320, 30, 8.0, 750),),
        (("족발", 700, 780, 30.0, 300), ("소주", 440, 40, 16.0, 360),),
        (("편의점 도시락", 750, 700, 12.0, 450), ("크림빵 2개", 500, 150, 28.0, 160),),
        (("샐러드", 120, 380, 11.5, 200), ("닭가슴살", 230, 300, 0.5, 150), ("현미밥", 300, 20, 0.5, 200),),
        (("된장찌개", 480, 700, 4.0, 400), ("공기밥", 300, 10, 0.0, 210),),
        (("닭가슴살", 460, 600, 0.0, 300), ("고구마", 400, 60, 20.0, 300), ("프로틴", 360, 90, 4.0, 90),),
        (("닭가슴살 샐러드", 400, 260, 8.0, 300), ("오렌지주스", 120, 40, 20.0, 250),),
        (("두부 스테이크", 330, 700, 3.5, 200), ("잡곡밥", 300, 10, 0.5, 210),),
    ),
    "snack": (
        (("스포츠음료", 180, 90, 12.0, 600), ("바나나 2개", 220, 10, 6.0, 240),),
        (("그릭요거트", 180, 190, 6.0, 150), ("블루베리", 100, 10, 9.0, 150),),
        (("바나나", 100, 10, 5.0, 110), ("우유", 120, 120, 4.0, 200),),
        (("견과", 150, 30, 1.0, 25), ("아메리카노", 20, 10, 0.0, 355),),
        (("두유", 130, 110, 8.0, 190),),
    ),
}


def _safe_commit(db: Session) -> None:
    """동시 기동이 같은 id 를 경쟁 삽입한 UNIQUE 충돌만 넘긴다(다른 시드와 같다)."""
    try:
        db.commit()
    except IntegrityError as e:
        db.rollback()
        sqlstate = getattr(getattr(e, "orig", None), "sqlstate", None)
        if sqlstate != _PG_UNIQUE_VIOLATION:
            raise
        logger.info("member log seed commit skipped (already seeded by a concurrent start)")


def seed_member_logs() -> None:
    """담당 회원의 최근 [LOG_DAYS] 일 끼니·운동 세션 시드(멱등)."""
    db: Session = SessionLocal()
    try:
        today = clock.today()
        for member_id, number in _MEMBER_NO.items():
            if db.get(models.User, member_id) is None:
                continue  # 계정 시드가 건너뛴 회원(이메일 충돌 등)
            split_daily_meals(db, member_id, number, today)
            _drop_routine_sessions(db, member_id)
        _safe_commit(db)
    finally:
        db.close()


def _is_daily_line(entry: models.DietEntry, member_id: str) -> bool:
    """하루를 한 줄로 남긴 시드 행인가 — `seed_roster`·`seed_member_data` 가 넣는다."""
    return entry.id.startswith(f"seed-roster-diet-{member_id}-") or (
        entry.id.startswith(f"seed-diet-{member_id}-") and entry.id.endswith("-agg")
    )


def split_daily_meals(
    db: Session, member_id: str, number: int, today: date
) -> None:
    """최근 [LOG_DAYS] 일의 하루 한 줄 시드를 같은 합계의 끼니 여럿으로 나눈다."""
    since = (today - timedelta(days=LOG_DAYS - 1)).isoformat()
    rows = db.scalars(
        select(models.DietEntry).where(
            models.DietEntry.user_id == member_id,
            models.DietEntry.date >= since,
            models.DietEntry.date <= today.isoformat(),
        )
    ).all()
    by_date: dict[str, list[models.DietEntry]] = {}
    for row in rows:
        by_date.setdefault(row.date, []).append(row)
    for day, entries in by_date.items():
        if any(e.id.startswith(MEAL_ID_PREFIX) for e in entries):
            # 이미 나눈 날. 한 줄 시드가 다시 깔렸으면 걷어 낸다 — 남기면 합계가
            # 두 번 잡힌다.
            for e in entries:
                if _is_daily_line(e, member_id):
                    db.delete(e)
            continue
        if len(entries) != 1 or not _is_daily_line(entries[0], member_id):
            continue  # 회원이 직접 남긴 기록이 있는 날은 건드리지 않는다
        line = entries[0]
        if line.total_calories <= 0:
            continue
        for meal in meals_for_day(
            member_id, number, date.fromisoformat(day),
            calories=line.total_calories,
            sodium_mg=line.sodium_mg,
            sugar_g=line.sugar_g,
        ):
            db.add(meal)
        db.delete(line)


def _meal_count(calories: int) -> int:
    """그날 끼니 수 — 트레이너 웹 데모 `_mealCountOf` 와 같다(한 끼 600kcal)."""
    return max(1, min(4, round(calories / 600)))


def _split(total: int, weights: list[float]) -> list[int]:
    """[total] 을 [weights] 비중대로 정수로 나눈다. 남는 몫은 가장 큰 칸이 맡는다."""
    s = sum(weights)
    w = weights if s > 0 else [1.0] * len(weights)
    ws = s if s > 0 else float(len(weights))
    out = [round(total * x / ws) for x in w]
    largest = max(range(len(out)), key=lambda i: out[i])
    out[largest] += total - sum(out)
    return out


def _macro_shares(day: date) -> tuple[float, float, float]:
    """(탄, 단, 지) 칼로리 비율 — 트레이너 웹 데모 `_macroShares` 와 같다."""
    carbs = 0.50 if day.weekday() % 2 == 0 else 0.45
    return carbs, 0.25, 1 - carbs - 0.25


def meals_for_day(
    member_id: str,
    number: int,
    day: date,
    *,
    calories: int,
    sodium_mg: int,
    sugar_g: float,
) -> list[models.DietEntry]:
    """하루 합계를 본보기 끼니에 나눠 담는다.

    본보기는 회원·날짜로 돌려 고른다. 칼로리는 칼로리 비중, 나트륨·당류는 그
    영양의 비중대로 나눠 짠 음식은 여전히 짜다. 합은 하루 합계와 정확히 같다.
    """
    slots = _MEAL_SLOTS[_meal_count(calories) - 1]
    day_no = (day - date(2000, 1, 1)).days
    templates = [
        _MEAL_TEMPLATES[slot][
            (number * 5 + day_no * 3 + k) % len(_MEAL_TEMPLATES[slot])
        ]
        for k, (slot, _time) in enumerate(slots)
    ]
    foods = [f for meal in templates for f in meal]
    kcal = _split(calories, [f[1] for f in foods])
    sodium = _split(sodium_mg, [f[2] for f in foods])
    sugar = [v / 10 for v in _split(round(sugar_g * 10), [f[3] for f in foods])]
    carbs_share, protein_share, fat_share = _macro_shares(day)
    out: list[models.DietEntry] = []
    offset = 0
    for k, ((slot, at), meal) in enumerate(zip(slots, templates)):
        rows = []
        for j, (name, base_kcal, _na, _sg, amount) in enumerate(meal):
            i = offset + j
            rows.append({
                "name": name,
                "amount_g": (
                    max(1, round(amount * kcal[i] / base_kcal)) if base_kcal else amount
                ),
                "calories": kcal[i],
                "sodium_mg": sodium[i],
                "sugar_g": sugar[i],
            })
        offset += len(meal)
        meal_kcal = sum(r["calories"] for r in rows)
        out.append(models.DietEntry(
            id=f"{MEAL_ID_PREFIX}{member_id}-{day.isoformat()}-{k}",
            user_id=member_id,
            date=day.isoformat(),
            meal_type=slot,
            time_label=at,
            foods_json=json.dumps(rows, ensure_ascii=False),
            total_calories=meal_kcal,
            carbs_g=round(meal_kcal * carbs_share / 4, 1),
            protein_g=round(meal_kcal * protein_share / 4, 1),
            fat_g=round(meal_kcal * fat_share / 9, 1),
            sodium_mg=sum(r["sodium_mg"] for r in rows),
            sugar_g=round(sum(r["sugar_g"] for r in rows), 1),
            engine="seed",
        ))
    return out


def _drop_routine_sessions(db: Session, member_id: str) -> None:
    """예전 시드가 요일 루틴으로 심은 `member` 세션을 지운다(멱등). (#3003)"""
    db.query(models.ExerciseSession).filter(
        models.ExerciseSession.user_id == member_id,
        models.ExerciseSession.id.like(f"{SESSION_ID_PREFIX}%"),
    ).delete(synchronize_session=False)
