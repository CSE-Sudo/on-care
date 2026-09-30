"""AI 챗봇 답이 요청 언어를 따른다(#2712). DB 없이 돈다.

영어 화면에서 보낸 대화에는 시스템 프롬프트 끝에 출력 언어 규칙이 붙고, LLM 이
실패했을 때의 대체 답도 영어다. 헤더가 없으면 지금까지처럼 한국어다.
"""
from __future__ import annotations

import re
from contextlib import contextmanager
from types import SimpleNamespace

from app.core.locale import _request_locale_ctx
from app.services.coach import chat

_HANGUL = re.compile("[가-힣]")


@contextmanager
def _english():
    token = _request_locale_ctx.set("en")
    try:
        yield
    finally:
        _request_locale_ctx.reset(token)


def _doc(title: str, content: str) -> SimpleNamespace:
    return SimpleNamespace(title=title, content=content)


def test_korean_keeps_the_system_prompt_as_is():
    assert chat._system_prompt() == chat._SYSTEM


def test_english_appends_the_output_rule():
    with _english():
        prompt = chat._system_prompt()
    assert prompt.startswith(chat._SYSTEM)
    assert "Output language" in prompt


def test_english_user_prompt_asks_in_english():
    with _english():
        prompt = chat._build_user_prompt("", [], "How much sodium is too much?")
    assert "As Oni" in prompt
    assert "How much sodium is too much?" in prompt


def test_fallback_replies_follow_the_locale():
    empty = {"personal": [], "public": []}
    personal = {"personal": [_doc("", "기록")], "public": []}
    public = {"personal": [], "public": [_doc("나트륨 가이드", "하루 2000mg 이하")]}

    assert _HANGUL.search(chat._fallback_reply(empty))
    with _english():
        for hits in (empty, personal):
            assert not _HANGUL.search(chat._fallback_reply(hits))
        reply = chat._fallback_reply(public)
    # 공공 자료 본문은 한국어 원문뿐이라 영어 답에 붙이지 않고 제목만 알린다.
    assert "하루 2000mg 이하" not in reply
    assert "나트륨 가이드" in reply
