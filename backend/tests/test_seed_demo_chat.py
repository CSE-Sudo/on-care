"""데모 채팅 시드(user-7d4e9a2c5f18) — 회원 앱·트레이너 앱과 같은 대화여야 한다. (#543)

김민수는 회원 앱 데모 사용자(user-7d4e9a2c5f18)와 같은 계정이라, 실서버로 붙여도
데모에서 보던 대화가 그대로 이어져야 한다. 같은 목록을 고정하는 짝:

* frontend/flutter/test/features/member_coach/demo_chat_thread_test.dart
* frontend/flutter_trainer/test/core/storage/demo_chat_thread_test.dart

DB 필요(로컬 skip, CI 의 Postgres 서비스에서 실행). client 픽스처가 init_db →
seed_member_health_data 를 먼저 돌린 상태를 검증한다.
"""
from __future__ import annotations

from sqlalchemy import select


_MEMBER_ID = "user-7d4e9a2c5f18"

# (sender, body) — 프론트 두 앱의 시드와 글자까지 같아야 한다. 백엔드는
# 회원을 'member' 로 저장하고 트레이너 API 응답에서만 'client' 로 바꾼다.
_EXPECTED: list[tuple[str, str]] = [
    ("trainer", "민수님, 지난주 기록 정리해 봤는데 요일마다 이행률이 들쭉날쭉하네요. 바쁜 요일이 정해져 있나요?"),
    ("member", "화요일이랑 목요일이 야근이 많아요 😥"),
    ("trainer", "그럼 그 이틀은 15분짜리 짧은 루틴으로 바꿔 둘게요. 안 하는 것보다 훨씬 낫습니다"),
    ("member", "그 정도면 퇴근하고도 할 수 있을 것 같아요"),
    ("trainer", "혈압약 드시는 시간은 그대로시죠? 유산소가 그 시간과 겹치지 않게 잡을게요"),
    ("member", "네, 아침 8시 그대로예요"),
    ("trainer", "확인했어요. 화·목은 15분 저강도로 바꿔서 보냈습니다 🙂"),
    ("trainer", "동작 순서는 이 파일로 정리해 뒀어요"),
    ("trainer", "민수님, 요즘 나트륨이 목표(2,000mg) 근처에서 자주 걸리네요. 국·찌개가 잦으신 편인가요?"),
    ("member", "회사 구내식당이라 국물이 늘 나와요 😅"),
    ("trainer", "국물만 절반 남기셔도 400~500mg은 빠져요. 그거 하나만 먼저 해보죠"),
    ("trainer", "이렇게 국은 건더기 위주로 드시면 돼요"),
    ("member", "오늘은 국물 안 마셨어요! 걷기도 25분 했습니다"),
    ("trainer", "좋아요 👏 그 한 가지만 지켜도 추이가 달라져요"),
    ("trainer", "내일 루틴은 걷기 20분으로 조금 늘려서 보냈어요. 주말까지 이 페이스로 가봐요"),
    ("trainer", "민수님, AI 식단 분석 잘 받았어요 👍 오늘 나트륨이 목표치를 좀 넘었는데 어떠셨어요?"),
    ("member", "찌개 먹을 때 국물을 많이 마셨나봐요 😅"),
    ("trainer", "그렇군요! 오늘 PT 후에 부상이나 불편한 데는 없으셨나요?"),
    ("member", "무릎이 가볍게 당기긴 했는데 괜찮아요"),
    ("trainer", "확인했어요. AI가 오늘 식단 기반으로 유산소 루틴을 추천했는데, 무릎 상태 감안해서 런닝 대신 걷기로 조정해서 보낼게요. 다음 PT 때 봐요 💪"),
]


def _seeded_thread(db_session):
    from app.models.models import ChatMessage

    return db_session.scalars(
        select(ChatMessage)
        .where(
            ChatMessage.member_id == _MEMBER_ID,
            ChatMessage.id.like("seed-chat-%"),
        )
        .order_by(ChatMessage.created_at, ChatMessage.id)
    ).all()


def test_demo_thread_matches_the_app_seeds(client, db_session):
    """본문·순서·보낸 쪽이 두 앱의 시드와 같다."""
    rows = _seeded_thread(db_session)
    assert [(r.sender, r.body) for r in rows] == _EXPECTED


def test_demo_thread_spans_three_days(client, db_session):
    """사흘치 대화가 30분짜리 수다로 뭉치지 않는다.

    시각을 전부 같은 시간대에 몰아넣으면 사흘 대화가 같은 오후에 오간 것처럼
    읽히고, 화면이 날짜로 묶는 자리(하루치 AI 분석 안내)도 하나로 뭉친다.
    '며칠에 걸쳤나(span)' 가 아니라 **서로 다른 날이 몇 개인가**를 본다 —
    대화한 날이 달력에서 연속일 필요는 없다.
    """
    rows = _seeded_thread(db_session)
    days = {r.created_at.date() for r in rows}
    assert len(days) == 3, f"대화한 날이 {len(days)}일입니다: {sorted(days)}"


def test_demo_thread_is_chronological(client, db_session):
    """스레드 정렬은 (created_at, id) 이므로 시각이 단조 증가해야 한다."""
    rows = _seeded_thread(db_session)
    times = [r.created_at for r in rows]
    assert times == sorted(times)
    assert len(set(times)) == len(times), "같은 시각의 메시지가 있어 순서가 흔들립니다."


def test_reseeding_overwrites_an_older_thread(client, db_session):
    """이미 시드된 DB 도 현재 대화로 갱신된다.

    전에는 id 가 있으면 건너뛰어서, 다섯 개짜리 옛 스레드를 가진 DB 가 앞
    다섯 개는 옛 본문 그대로 두고 뒤에 새 메시지만 덧붙였다 — 앞뒤가 다른
    스레드가 된다. 공유 DB 는 이미 옛 시드를 갖고 있어 실제로 겪는 경로다.
    """
    from app.db.seed_member_data import _seed_chat
    from app.models.models import ChatMessage

    first = _seeded_thread(db_session)[0]
    first.body = "옛 시드 본문"
    stray_id = f"seed-chat-{_MEMBER_ID}-999"
    db_session.add(ChatMessage(
        id=stray_id,
        trainer_id=first.trainer_id,
        member_id=_MEMBER_ID,
        sender="trainer",
        body="이제 없는 메시지",
        created_at=first.created_at,
    ))
    db_session.commit()

    _seed_chat(db_session, _MEMBER_ID)
    db_session.expire_all()

    rows = _seeded_thread(db_session)
    assert [(r.sender, r.body) for r in rows] == _EXPECTED
    assert db_session.get(ChatMessage, stray_id) is None


def test_knee_message_is_seeded_as_a_chat_insight_memo(client, db_session):
    """무릎 불편을 말한 대화가 감지 메모로도 남는다 (#1655).

    데모 계정이 실 API 로 프로그램 탭을 열었을 때 `최근 7일 AI 감지 메모` 칸이
    비어 있으면, 트레이너 웹 로컬 데모와 같은 화면이 아니다. `insight_id` 가 앱이
    만드는 값과 같은 규칙이라, 채팅에서 그 배너를 눌러도 메모가 두 번 쌓이지 않는다.
    """
    from app.models.models import TrainerClientMemo

    memos = db_session.scalars(
        select(TrainerClientMemo)
        .where(
            TrainerClientMemo.member_id == _MEMBER_ID,
            TrainerClientMemo.source == "chat_insight",
        )
        .order_by(TrainerClientMemo.created_at.desc())
    ).all()

    assert [m.body for m in memos] == ["무릎 불편 감지"]
    knee = memos[0]
    assert knee.insight_kind == "discomfort"
    # `"{메시지 id}:discomfort"` — 앱의 ChatContextInsight.id 와 같은 규칙.
    assert knee.insight_id == f"seed-chat-{_MEMBER_ID}-18:discomfort"


def test_trainer_files_are_seeded_in_the_same_places_as_the_apps(client, db_session):
    """트레이너가 보낸 PDF·사진이 두 앱 데모와 같은 자리·같은 바이트다. (#2788)

    바이트는 프론트 번들 파일과 같아야 한다 — 두 앱이 보여 주는 문서와 실서버가
    내려 주는 문서가 달라지지 않게.
    """
    from pathlib import Path

    from app.services import chat_image_storage, report_pdf_storage

    rows = [r for r in _seeded_thread(db_session) if r.attachment_file_id]
    assert [(r.body, r.attachment_type, r.attachment_file_name) for r in rows] == [
        ("동작 순서는 이 파일로 정리해 뒀어요", "pdf", "tue-thu-15min-program.pdf"),
        ("이렇게 국은 건더기 위주로 드시면 돼요", "image", "soup-example.jpeg"),
    ]
    assert all(r.sender == "trainer" for r in rows)

    frontend = Path(__file__).resolve().parents[2] / "frontend" / "flutter"
    pdf, image = rows
    pdf_bytes = report_pdf_storage.path_for(pdf.attachment_file_id).read_bytes()
    assert pdf_bytes.startswith(b"%PDF")
    assert pdf.attachment_file_size == len(pdf_bytes)
    # 앱 번들의 PDF 는 #2663 이 넣는다. 그 PR 이 들어온 뒤로는 바이트까지 같아야 한다.
    app_pdf = frontend / "assets" / "demo" / "coach-program-tue-thu.pdf"
    if app_pdf.exists():
        assert pdf_bytes == app_pdf.read_bytes()

    path, media_type = chat_image_storage.path_for(image.attachment_file_id)
    assert media_type == "image/jpeg"
    image_bytes = path.read_bytes()
    assert image_bytes == (
        frontend / "assets" / "images" / "diet-doenjang-rice.jpeg"
    ).read_bytes()
    assert image.attachment_file_size == len(image_bytes)


def test_reseeding_drops_the_memo_left_at_an_old_message_id(client, db_session):
    """순번이 밀려 메모 id 가 바뀌어도 옛 id 의 메모가 남지 않는다. (#2788)"""
    from app.db.seed_member_data import seed_member_health_data
    from app.db.seed_trainer import TRAINER_ID
    from app.models.models import TrainerClientMemo

    db_session.add(TrainerClientMemo(
        id=f"seed-memo-{_MEMBER_ID}-16",
        trainer_id=TRAINER_ID,
        member_id=_MEMBER_ID,
        body="무릎 불편 감지",
        source="chat_insight",
        insight_id=f"seed-chat-{_MEMBER_ID}-16:discomfort",
        insight_kind="discomfort",
    ))
    db_session.commit()

    seed_member_health_data()
    db_session.expire_all()

    ids = db_session.scalars(
        select(TrainerClientMemo.id).where(
            TrainerClientMemo.member_id == _MEMBER_ID,
            TrainerClientMemo.source == "chat_insight",
        )
    ).all()
    assert ids == [f"seed-memo-{_MEMBER_ID}-18"]
