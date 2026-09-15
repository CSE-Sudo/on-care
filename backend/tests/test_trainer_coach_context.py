"""트레이너의 고객 코칭 문답에 맥락을 잇는다 (#588).

두 성질을 함께 지켜야 한다:
  * 후속 질문이 앞 문답을 참조한다 (예전엔 history 를 항상 [] 로 넘겨 매번 단발)
  * 그 문답이 **회원 앱에 새지 않는다** — 검색 스코프는 회원이지만 대화의 주인은
    트레이너다. 같은 스레드에 넣으면 회원이 자기가 하지 않은 대화를 보게 된다.
"""
from __future__ import annotations

import pytest

from app.services.coach import chat as coach_chat
from app.services.coach import conversation


def _login(client, username: str, password: str = "oncare123") -> str:
    r = client.post(
        "/v1/auth/login", data={"username": username, "password": password}
    )
    assert r.status_code == 200, r.text
    return r.json()["access_token"]


def _headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def seen_prompts(monkeypatch):
    """LLM 을 막고, 프롬프트에 실린 히스토리를 그대로 본다."""
    prompts: list[str] = []

    class _StubLLM:
        def generate(self, system_prompt: str, user_prompt: str):
            prompts.append(user_prompt)

            class _R:
                text = "확인했습니다. 다음 주는 하체 부하를 낮추시죠."

            return _R()

    monkeypatch.setattr(coach_chat, "get_coach_llm", lambda *a, **k: _StubLLM())
    return prompts


def _ask(client, token: str, member_id: str, message: str):
    return client.post(
        f"/v1/trainer/clients/{member_id}/ai-coach",
        headers=_headers(token),
        json={"message": message},
    )


def _first_client_id(client, token: str) -> str:
    r = client.get("/v1/trainer/clients", headers=_headers(token))
    assert r.status_code == 200, r.text
    return r.json()[0]["id"]


def test_a_follow_up_question_carries_the_previous_exchange(
    client, seen_prompts
):
    token = _login(client, "trainer@oncare.com")
    member_id = _first_client_id(client, token)

    first = _ask(client, token, member_id, "이 회원 무릎 상태 어떻게 볼까요?")
    assert first.status_code == 200, first.text
    second = _ask(client, token, member_id, "그럼 다음 주는요?")
    assert second.status_code == 200, second.text

    # 두 번째 요청의 프롬프트에 첫 질문과 답이 들어 있어야 한다.
    assert "이 회원 무릎 상태" in seen_prompts[-1]
    assert "이전 대화" in seen_prompts[-1]


def test_the_first_question_has_no_history(client, seen_prompts):
    """빈 스레드에서 '이전 대화' 블록이 붙으면 모델이 없는 맥락을 지어낸다."""
    token = _login(client, "trainer@oncare.com")
    member_id = _first_client_id(client, token)

    # 이 테스트만의 깨끗한 스레드를 쓰기 위해 다른 고객을 고른다.
    roster = client.get("/v1/trainer/clients", headers=_headers(token)).json()
    if len(roster) < 2:
        pytest.skip("고객이 2명 미만이면 빈 스레드를 확보할 수 없다.")
    fresh_member = roster[1]["id"]

    _ask(client, token, fresh_member, "이 회원 식단은 어떤가요?")

    assert "이전 대화" not in seen_prompts[-1]
    assert member_id != fresh_member


def test_history_is_restorable_after_reopening_the_sheet(client, seen_prompts):
    token = _login(client, "trainer@oncare.com")
    member_id = _first_client_id(client, token)

    _ask(client, token, member_id, "이 회원 운동량 평가해 주세요")

    r = client.get(
        f"/v1/trainer/clients/{member_id}/ai-coach", headers=_headers(token)
    )

    assert r.status_code == 200, r.text
    rows = r.json()
    assert [m["role"] for m in rows[-2:]] == ["user", "coach"]
    assert rows[-2]["content"] == "이 회원 운동량 평가해 주세요"


def test_trainer_questions_never_appear_in_the_member_app(
    client, db_session, seen_prompts
):
    """가장 중요한 성질 — 회원이 자기가 하지 않은 대화를 보면 안 된다.

    담당 트레이너가 연결된 회원은 앱에서 AI 챗봇 대화를 열 수 없다(#1823) — 그래도
    회원 본인 스레드에 트레이너 질문이 섞이지 않는다는 성질은 스레드를 직접 읽어
    지킨다. 연결이 풀려 회원이 다시 AI 챗봇을 열면 그 스레드가 보이기 때문이다.
    """
    trainer_token = _login(client, "trainer@oncare.com")
    member_id = _first_client_id(client, trainer_token)

    secret = "트레이너만 보는 질문입니다 이 회원 체중 관리 어떻게 할까요"
    _ask(client, trainer_token, member_id, secret)

    member_thread = conversation.load_messages(db_session, member_id)
    assert all(secret not in m.content for m in member_thread)

    member_token = _login(client, "minsu@oncare.com")
    r = client.get("/v1/ai-coach/messages", headers=_headers(member_token))
    assert r.status_code == 403, r.text


def test_member_chat_does_not_leak_into_the_trainer_thread(
    client, db_session, seen_prompts
):
    """반대 방향도 막힌다 — 회원의 사적인 코치 대화가 트레이너에게 보이면 안 된다.

    회원 본인 스레드에 대화를 남겨 두고(트레이너가 연결되기 전에 나눈 대화)
    트레이너 문답 스레드에 나오지 않는지 본다.
    """
    trainer_token = _login(client, "trainer@oncare.com")
    member_id = _first_client_id(client, trainer_token)
    private = "제 개인적인 고민을 온이에게만 말합니다"
    conversation.append_exchange(
        db_session, member_id, question=private, reply="들어 드릴게요", sources=[]
    )

    r = client.get(
        f"/v1/trainer/clients/{member_id}/ai-coach", headers=_headers(trainer_token)
    )

    assert r.status_code == 200, r.text
    assert all(private not in m["content"] for m in r.json())


def test_history_is_scoped_to_the_asking_trainer(client):
    """담당이 아닌 회원의 스레드는 존재조차 드러내지 않는다(404)."""
    token = _login(client, "trainer@oncare.com")

    r = client.get(
        "/v1/trainer/clients/not-my-member/ai-coach", headers=_headers(token)
    )

    assert r.status_code == 404


def test_a_member_account_cannot_read_a_trainer_thread(client):
    token = _login(client, "minsu@oncare.com")

    r = client.get(
        "/v1/trainer/clients/anyone/ai-coach", headers=_headers(token)
    )

    assert r.status_code == 403
