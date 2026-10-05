"""데모 트레이너의 후속 관리·메모·프로그램 초안·지난 PT/상담 메모 시드. (#2731)

백엔드 시드에는 이 넷이 없어, 실서버 데모 계정에서 대시보드 오늘 할 일·프로그램 초안
목록·AI 루틴 추천 근거의 `트레이너 메모`·`PT 피드백`·`상담 메모` 가 비어 있었다.
트레이너 웹 데모(#2667, `frontend/flutter_trainer/lib/core/storage/seed_trainer_notes.dart`
·`seed_data.dart` 의 `_pastPtNotes`·`_pastConsults`)와 같은 내용을 심는다.

**한 번만 심는다.** 후속 관리·메모·초안은 트레이너가 직접 고치고 지우는 기록이라,
그 표에 데모 트레이너의 행이 하나라도 있으면 건드리지 않는다 — 재기동마다 다시
심으면 지운 기록이 되살아난다. 지난 PT 메모는 비어 있는 시드 수업에만, 지난 상담은
최근 30일에 시드 상담이 없을 때만 넣는다.
"""
from __future__ import annotations

import json
import logging
from datetime import date, datetime, time, timedelta

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session
from sqlalchemy.orm.attributes import flag_modified

from app.core import clock
from app.core.week import monday_of
from app.db.seed_member_logs import current_seed_sentence, current_seed_text
from app.db.seed_trainer import TRAINER_ID, _MEMBERS
from app.db.session import SessionLocal
from app.models import models

logger = logging.getLogger(__name__)

_PG_UNIQUE_VIOLATION = "23505"

#: 지난 상담 id 머리.
CONSULT_ID_PREFIX = "seed-consult-"

#: (회원, 제목, 오늘부터 며칠 뒤가 예정일, 화면 이동 자리, 며칠 전에 만들었나,
#: 며칠 전에 끝냈나 — 없으면 미완료). 오늘 할 일·기한 지남·예정·완료가 한 번씩 보이게.
_FOLLOW_UPS: tuple[tuple[str, str, int, str, int, int | None], ...] = (
    ("user-sera", "허리 통증 경과 확인 메시지", 0, "message", 2, None),
    ("user-junhyuk", "노쇼 반복 — PT 시간대 재조정 제안", -1, "schedule", 4, None),
    ("user-dohyun", "첫 주 식단 기록 독려", 0, "diet", 1, None),
    ("user-hayun", "재활 루틴 강도 조정 검토", 1, "program", 3, None),
    ("user-kangseoyeon", "주말 식단 기록 점검", 3, "diet", 2, None),
    ("user-taekyung", "단백질 섭취 계획 공유", 5, "general", 1, None),
    ("user-jisu", "인바디 측정 일정 잡기", -3, "schedule", 7, 3),
)

#: (회원, 며칠 전, 본문, 운동 기록 카드에서 남긴 메모인가, 분류 #2622). AI 근거 `트레이너 메모`
#: (최근 14일)가 읽는다.
_MEMOS: tuple[tuple[str, int, str, bool, str], ...] = (
    ("user-sera", 3, "혈압약 복용 시간이 아침 7시로 바뀜. 고강도 인터벌은 당분간 빼기.", False, "life"),
    ("user-yuna", 5, "무릎 굴곡 110°까지 통증 없음. 다음 주부터 스쿼트 깊이를 조금씩 늘리기.", False, "pain"),
    ("user-junhyuk", 8, "야근은 주로 화·목. 그날은 15분 홈트로 대신하도록 안내함.", False, "life"),
    ("user-taekyung", 2, "벌크업 중 체중은 주 0.3kg 증가가 목표. 저녁 탄수화물 늘리기로 합의.", False, "diet"),
    ("user-jiho", 6, "회식이 있는 주는 점심을 가볍게 — 본인이 먼저 제안함.", False, "diet"),
    ("user-kangseoyeon", 1, "주말 러닝은 혼자서도 꾸준히 이어 가는 중.", True, "exercise"),
)


def _strength(name: str, sets: int, reps: int, weight: float) -> dict:
    return {
        "name": name, "type": "근력", "sets": sets, "reps": reps,
        "weight": weight, "source": "trainer",
    }


def _timed(name: str, kind: str, minutes: int) -> dict:
    return {
        "name": name, "type": kind, "duration": minutes,
        "duration_seconds": minutes * 60, "source": "trainer",
    }


#: (이름, 목표, 기간, 메모, 세션[(이름, 운동[])], 며칠 전에 고쳤나). 누구에게 배정한
#: 것이 아니라, 비슷한 회원에게 다시 쓰려고 남겨 둔 틀이다.
_DRAFTS: tuple[tuple[str, str, str, str, list[tuple[str, list[dict]]], int], ...] = (
    (
        "무릎 재활 하체 강화",
        "무릎 가동범위 회복 · 하체 근력",
        "4주",
        "통증 척도 2 이하에서만 진행. 가동범위는 주마다 10°씩 늘린다.",
        [
            ("1회차 · 가동범위", [
                _timed("무릎 가동범위", "스트레칭", 10),
                _strength("레그프레스", 3, 12, 40),
                _timed("사이클", "유산소", 15),
            ]),
            ("2회차 · 근력", [
                _strength("스쿼트", 3, 10, 20),
                _strength("런지", 3, 10, 0),
            ]),
        ],
        4,
    ),
    (
        "체지방 감량 서킷",
        "체지방 감량 · 심폐 지구력",
        "8주",
        "식단 기록이 주 5일 이상인 회원에게. 인터벌 강도는 대화가 끊길 정도까지만.",
        [
            ("1회차 · 전신 서킷", [
                _strength("버피", 3, 12, 0),
                _strength("마운틴 클라이머", 3, 20, 0),
                _timed("러닝", "유산소", 20),
            ]),
        ],
        9,
    ),
    (
        "운동 습관 첫 달",
        "주 3회 운동 습관",
        "4주",
        "처음 운동하는 회원용. 무게보다 자세, 횟수보다 꾸준함.",
        [
            ("1회차 · 기초", [
                _timed("걷기", "유산소", 20),
                _strength("맨몸 스쿼트", 3, 15, 0),
                _timed("전신 스트레칭", "스트레칭", 10),
            ]),
        ],
        15,
    ),
)

#: 지난 PT 메모 — [0] 은 지난주, [1] 은 2주 전. 회원별 그 주 첫 수업에만 단다.
#: AI 근거 `PT 피드백`(최근 14일)이 읽는다. 트레이너 웹 데모 `_pastPtNotes` 와 같다.
_PAST_PT_NOTES: tuple[dict[str, str], ...] = (
    {
        "user-jisu": "인터벌 6세트 완주. 마지막 두 세트에서 호흡이 빨리 올라와 휴식을 90초로 늘림.",
        "user-sungho": "벤치프레스 70kg 4×6 성공. 다음 주 72.5kg 시도.",
        "user-woojin": "하프 마라톤 대비 템포런 후 햄스트링 뻣뻣함. 폼롤러 10분 추가.",
        "user-dohyun": "데드리프트 힙힌지 패턴 안정. 허리 통증 없음, 중량 유지.",
        "user-yuna": "무릎 굴곡 110°까지 통증 없음. 스텝업 높이 한 단계 올림.",
        "user-sera": "허리 뻐근함 호소해 코어 운동을 버드독 위주로 바꿈. 혈압 측정 후 시작.",
        "user-jiho": "스쿼트 깊이 개선. 회식 다음 날이라 유산소는 20분으로 줄임.",
        "user-junhyuk": "야근 뒤 늦게 도착해 30분만 진행. 상체 위주로 압축.",
        "user-seojin": "전신 서킷 3라운드 무리 없음. 식단 얘기는 다음 상담에서 이어 가기로.",
        "user-kangseoyeon": "주말 과식 얘기 나눔. 스쿼트 50kg 4×10 안정적.",
        "user-taekyung": "벌크업 중 벤치프레스 45kg 도달. 단백질 쉐이크 운동 직후로 옮김.",
        "user-hayun": "재활 밴드 운동 통증 없이 완료. 다음 주 맨몸 런지 추가.",
        "user-gayoung": "3주 만의 PT. 체력 저하가 커서 강도를 70%로 낮춰 진행.",
        "user-eunchae": "첫 PT. 기구 사용법 위주로 안내, 스쿼트 자세 좋음.",
    },
    {
        "user-jisu": "사이클 30분 + 하체 근력. 무릎 정렬 좋아짐.",
        "user-sungho": "데드리프트 100kg 3×5. 그립 약해져 스트랩 사용 권유.",
        "user-woojin": "장거리 러닝 후 회복 주간. 가동성 위주로 가볍게.",
        "user-yuna": "레그프레스 가동범위 70%까지. 통증 척도 1/10.",
        "user-sera": "걷기 속도 높임. 운동 후 혈압 정상 범위.",
        "user-jiho": "체중 정체 이야기. 저녁 탄수화물 절반 줄이기로 합의.",
        "user-junhyuk": "당일 취소 후 보강 PT. 컨디션 좋음.",
        "user-seojin": "플랭크 90초 달성. 나트륨 높은 점심 메뉴 대안 안내.",
        "user-kangseoyeon": "인터벌 후 어지럼 없음. 물 섭취 늘리라고 안내.",
        "user-taekyung": "하체 볼륨 늘림. 식사량 늘리는 게 힘들다고 함.",
        "user-hayun": "출산 후 코어 재활 4주차. 복직근 이개 1.5cm.",
        "user-gayoung": "PT 시간대 바꾸고 싶다고 함. 상담 잡기로.",
    },
)

#: 지난 상담 — (며칠 전, 회원, 메모). AI 근거 `상담 메모`(최근 30일)가 읽는다.
#: 11:00 은 주간 PT 자리표(`_WEEKLY_PT`)·오늘 타임라인이 쓰지 않는 칸이다.
_PAST_CONSULTS: tuple[tuple[int, str, str], ...] = (
    (11, "user-jiho", "식습관 상담. 회식이 주 2회라 야식 빈도부터 줄이기로 함."),
    (18, "user-sera", "혈압 관리 상담. 가정 혈압 기록을 PT 전에 공유하기로 함."),
    (25, "user-yuna", "재활 목표 재설정 상담. 병원 소견상 무릎 굴곡은 120°까지."),
)
_CONSULT_TIME = "11:00"
_CONSULT_MINUTES = 45


def _safe_commit(db: Session) -> None:
    try:
        db.commit()
    except IntegrityError as e:
        db.rollback()
        sqlstate = getattr(getattr(e, "orig", None), "sqlstate", None)
        if sqlstate != _PG_UNIQUE_VIOLATION:
            raise
        logger.info("trainer notes seed commit skipped (already seeded by a concurrent start)")


def _at(day: date, hour: int) -> datetime:
    return datetime.combine(day, time(hour, 0), tzinfo=clock.SEOUL)


def seed_trainer_notes() -> None:
    """데모 트레이너의 기록 시드(멱등). 트레이너 계정이 없으면 건너뛴다."""
    db: Session = SessionLocal()
    try:
        if db.scalar(
            select(models.User.id).where(
                models.User.id == TRAINER_ID, models.User.role == "trainer"
            )
        ) is None:
            return
        today = clock.today()
        valid = set(
            db.scalars(
                select(models.TrainerClient.member_id).where(
                    models.TrainerClient.trainer_id == TRAINER_ID
                )
            ).all()
        )
        seed_follow_ups(db, today, valid)
        seed_memos(db, today, valid)
        seed_drafts(db, today)
        seed_past_pt_notes(db, today)
        seed_past_consults(db, today, valid)
        _safe_commit(db)
    finally:
        db.close()


def _trainer_has(db: Session, model, *where) -> bool:
    return db.scalar(
        select(model.id).where(model.trainer_id == TRAINER_ID, *where).limit(1)
    ) is not None


def seed_follow_ups(db: Session, today: date, valid: set[str]) -> None:
    if _trainer_has(db, models.TrainerFollowUpTask):
        _rename_seed_follow_ups(db)
        return
    for i, (member, title, due, context, created_ago, done_ago) in enumerate(_FOLLOW_UPS):
        if member not in valid:
            continue
        created = _at(today - timedelta(days=created_ago), 21)
        completed = None if done_ago is None else _at(today - timedelta(days=done_ago), 19)
        db.add(models.TrainerFollowUpTask(
            id=f"seed-followup-{i}",
            trainer_id=TRAINER_ID,
            member_id=member,
            title=title,
            due_date=(today + timedelta(days=due)).isoformat(),
            status="pending" if completed is None else "completed",
            context_type=context,
            created_at=created,
            updated_at=completed or created,
            completed_at=completed,
        ))


def _rename_seed_follow_ups(db: Session) -> None:
    """이미 넣은 시드 할 일(`seed-followup-`)의 제목을 지금 시드 문장으로 고친다.

    할 일은 트레이너에게 하나라도 있으면 통째로 건너뛰므로, 문장을 바꿔도 이미
    시드된 DB 에는 옛 제목이 남는다(#3202). 옛 문장과 정확히 같은 제목만 바꾸고
    상태·기한·수정 시각은 그대로 둔다.
    """
    for row in db.scalars(
        select(models.TrainerFollowUpTask).where(
            models.TrainerFollowUpTask.trainer_id == TRAINER_ID,
            models.TrainerFollowUpTask.id.like("seed-followup-%"),
        )
    ):
        renamed = current_seed_sentence(row.title)
        if renamed != row.title:
            row.title = renamed
            # 표기만 고친 것을 방금 손본 할 일처럼 보이지 않게 수정 시각을 둔다.
            flag_modified(row, "updated_at")


def seed_memos(db: Session, today: date, valid: set[str]) -> None:
    if _trainer_has(
        db, models.TrainerClientMemo,
        models.TrainerClientMemo.source.in_(("trainer", "exercise_memo")),
    ):
        return
    for i, (member, days_ago, body, member_log, category) in enumerate(_MEMOS):
        if member not in valid:
            continue
        day = today - timedelta(days=days_ago)
        at = _at(day, 22)
        db.add(models.TrainerClientMemo(
            id=f"seed-memo-note-{i}",
            trainer_id=TRAINER_ID,
            member_id=member,
            body=body,
            source="exercise_memo" if member_log else "trainer",
            ref_kind="day" if member_log else "",
            ref_date=day.isoformat() if member_log else None,
            category=category,
            created_at=at,
            updated_at=at,
        ))


def seed_drafts(db: Session, today: date) -> None:
    if _trainer_has(db, models.TrainerProgramDraft):
        _rename_seed_drafts(db)
        return
    for i, (name, goal, period, memo, sessions, updated_ago) in enumerate(_DRAFTS):
        at = _at(today - timedelta(days=updated_ago), 23)
        db.add(models.TrainerProgramDraft(
            id=f"seed-draft-{i}",
            trainer_id=TRAINER_ID,
            name=name,
            goal=goal,
            period=period,
            memo=memo,
            sessions_json=json.dumps(
                [
                    {
                        "id": f"session-{s + 1}",
                        "name": session_name,
                        "exercises": [
                            {"id": f"seed-draft-{i}-{s}-{x}", **exercise}
                            for x, exercise in enumerate(exercises)
                        ],
                    }
                    for s, (session_name, exercises) in enumerate(sessions)
                ],
                ensure_ascii=False,
            ),
            created_at=at,
            updated_at=at,
        ))


def _rename_seed_drafts(db: Session) -> None:
    """이미 넣은 시드 초안(`seed-draft-`)의 운동 이름을 지금 시드 표기로 고친다.

    초안은 트레이너에게 하나라도 있으면 통째로 건너뛰므로, 표기를 바꿔도 이미
    시드된 DB 에는 옛 이름(`런닝`)이 남는다(#3201). 바뀐 표기만 갈아 끼우고 트레이너가
    고친 다른 값과 수정 시각은 그대로 둔다.
    """
    for row in db.scalars(
        select(models.TrainerProgramDraft).where(
            models.TrainerProgramDraft.trainer_id == TRAINER_ID,
            models.TrainerProgramDraft.id.like("seed-draft-%"),
        )
    ):
        renamed = current_seed_text(row.sessions_json)
        if renamed != row.sessions_json:
            row.sessions_json = renamed
            # 수정 시각은 있던 값 그대로 — 표기만 고친 것을 트레이너가 방금 고친
            # 초안처럼 맨 위로 올리지 않는다. 값을 SET 에 넣어야 `onupdate` 가
            # 지금 시각으로 바꾸지 않는다.
            flag_modified(row, "updated_at")


def seed_past_pt_notes(db: Session, today: date) -> None:
    """지난 두 주 회원별 첫 시드 PT 에 수업 메모를 단다 — 비어 있을 때만."""
    monday = monday_of(today)
    for back, notes in enumerate(_PAST_PT_NOTES, start=1):
        week_monday = monday - timedelta(weeks=back)
        week_sunday = week_monday + timedelta(days=6)
        rows = db.scalars(
            select(models.TrainerSchedule)
            .where(
                models.TrainerSchedule.trainer_id == TRAINER_ID,
                models.TrainerSchedule.id.like("seed-pt-%"),
                models.TrainerSchedule.date >= week_monday.isoformat(),
                models.TrainerSchedule.date <= week_sunday.isoformat(),
            )
            .order_by(models.TrainerSchedule.date, models.TrainerSchedule.time)
        ).all()
        seen: set[str] = set()
        for row in rows:
            if row.member_id is None or row.member_id in seen:
                continue
            seen.add(row.member_id)
            note = notes.get(row.member_id)
            if note and not row.note:
                row.note = note
    # 이미 메모가 달린 시드 PT 는 위에서 건너뛰므로, 옛 문장으로 단 메모만 지금
    # 문장으로 고친다(#3202). 트레이너가 고쳐 쓴 메모는 표에 없어 그대로다.
    for row in db.scalars(
        select(models.TrainerSchedule).where(
            models.TrainerSchedule.trainer_id == TRAINER_ID,
            models.TrainerSchedule.id.like("seed-pt-%"),
            models.TrainerSchedule.note != "",
        )
    ):
        renamed = current_seed_sentence(row.note)
        if renamed != row.note:
            row.note = renamed


def seed_past_consults(db: Session, today: date, valid: set[str]) -> None:
    """지난 상담을 둔다 — 최근 30일에 시드 상담이 하나도 없을 때만."""
    since = (today - timedelta(days=30)).isoformat()
    if _trainer_has(
        db, models.TrainerSchedule,
        models.TrainerSchedule.id.like(f"{CONSULT_ID_PREFIX}%"),
        models.TrainerSchedule.date >= since,
    ):
        return
    names = {user_id: name for user_id, _email, name, *_ in _MEMBERS}
    for days_ago, member, note in _PAST_CONSULTS:
        if member not in valid:
            continue
        day = (today - timedelta(days=days_ago)).isoformat()
        row_id = f"{CONSULT_ID_PREFIX}{member}-{day}"
        if db.get(models.TrainerSchedule, row_id) is not None:
            continue
        db.add(models.TrainerSchedule(
            id=row_id,
            trainer_id=TRAINER_ID,
            member_id=member,
            date=day,
            time=_CONSULT_TIME,
            client_name=names.get(member, ""),
            type="상담",
            duration_minutes=_CONSULT_MINUTES,
            status="완료",
            note=note,
            program_json="[]",
        ))
