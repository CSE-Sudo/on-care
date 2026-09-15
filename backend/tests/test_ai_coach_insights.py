"""AI 챗봇 통증·부정적 반응 감지. (#1824)

규칙은 트레이너 웹 채팅 감지(`chat_context_insight.dart`)와 같다. 오탐 사례(낱말의
꼬리·다른 낱말)를 함께 못 박아, 한쪽만 고쳐 두 채팅이 같은 문장을 다르게 읽는 일을 막는다.
"""
from __future__ import annotations

from datetime import timedelta
from uuid import uuid4

import pytest

from app.services.coach import insights


@pytest.mark.parametrize(
    ("text", "kind", "part"),
    [
        ("무릎이 아파요", insights.KIND_DISCOMFORT, "무릎"),
        ("어제부터 허리가 뻐근해요", insights.KIND_DISCOMFORT, "허리"),
        ("발목이 좀 부었어요", insights.KIND_DISCOMFORT, "발목"),
        ("목이 당겨요", insights.KIND_DISCOMFORT, "목"),
        ("손목 통증이 있어요", insights.KIND_DISCOMFORT, "손목"),
        ("어깨가 불편해요", insights.KIND_DISCOMFORT, "어깨"),
        ("그냥 좀 아팠어요", insights.KIND_DISCOMFORT, None),
        ("My lower back aches", insights.KIND_DISCOMFORT, "Back"),
        ("my knee hurts", insights.KIND_DISCOMFORT, "Knee"),
        ("오늘은 너무 힘들어서 못 했어요", insights.KIND_NEGATIVE, None),
        ("운동 포기하고 싶어요", insights.KIND_NEGATIVE, None),
        ("I gave up today", insights.KIND_NEGATIVE, None),
    ],
)
def test_detects_the_same_signals_as_trainer_chat(text, kind, part):
    found = insights.detect(text)
    assert found is not None, text
    assert found.kind == kind
    assert found.body_part == part


@pytest.mark.parametrize(
    "text",
    [
        "목요일에 운동할게요",  # 목요일의 목
        "이번 달 목표를 세웠어요",  # 목표의 목
        "골목에서 걸었어요",  # 다른 낱말의 꼬리
        "아파트 계단을 올랐어요",  # 아파트
        "아프리카 여행 가요",  # 아프리카
        "마무리 스트레칭까지 했어요",  # 마무리의 무리
        "허리띠를 샀어요",  # 허리띠
        "I'm back at the gym",  # back 은 부위가 아니다
        "오늘 샐러드 먹었어요",
        "",
    ],
)
def test_does_not_flag_look_alike_words(text):
    assert insights.detect(text) is None


def test_discomfort_wins_over_negative_in_one_message():
    found = insights.detect("무릎이 아파서 못 했어요")
    assert found == insights.Insight(kind=insights.KIND_DISCOMFORT, body_part="무릎")


def _member_token(client) -> tuple[str, str]:
    email = f"insight-{uuid4().hex[:10]}@oncare.com"
    r = client.post(
        "/v1/auth/register", json={"email": email, "password": "insight-pw-1", "name": "감지"}
    )
    assert r.status_code == 201, r.text
    token = client.post(
        "/v1/auth/login", data={"username": email, "password": "insight-pw-1"}
    ).json()["access_token"]
    return r.json()["id"], token


def test_history_and_insight_list_cover_the_last_30_days(client, db_session):
    """저장된 대화의 회원 메시지마다 감지를 싣고, 30일이 지난 메시지는 기록에서 뺀다."""
    from app.core import clock
    from app.services.coach import conversation

    member_id, token = _member_token(client)
    headers = {"Authorization": f"Bearer {token}"}
    conversation.append_exchange(
        db_session, member_id, question="무릎이 아파요", reply="쉬어 가세요", sources=[]
    )
    conversation.append_exchange(
        db_session, member_id, question="오늘 샐러드 먹었어요", reply="좋아요", sources=[]
    )
    old = conversation.append_exchange(
        db_session, member_id, question="허리가 뻐근해요", reply="스트레칭", sources=[]
    )
    from sqlalchemy import update

    from app.models.models import AiMessage

    db_session.execute(
        update(AiMessage)
        .where(AiMessage.conversation_id == old.id, AiMessage.content == "허리가 뻐근해요")
        .values(created_at=clock.now() - timedelta(days=31))
    )
    db_session.commit()

    history = client.get("/v1/ai-coach/messages", headers=headers)
    assert history.status_code == 200, history.text
    by_text = {m["content"]: m for m in history.json()["messages"]}
    assert by_text["무릎이 아파요"]["insight"] == {"kind": "discomfort", "body_part": "무릎"}
    assert by_text["오늘 샐러드 먹었어요"]["insight"] is None
    assert by_text["쉬어 가세요"]["insight"] is None

    listed = client.get("/v1/ai-coach/insights", headers=headers)
    assert listed.status_code == 200, listed.text
    body = listed.json()
    assert body["window_days"] == 30
    assert [i["text"] for i in body["insights"]] == ["무릎이 아파요"]
    assert body["insights"][0]["kind"] == "discomfort"
    assert body["insights"][0]["body_part"] == "무릎"
