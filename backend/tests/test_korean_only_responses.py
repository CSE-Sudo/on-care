"""서버 문장은 한국어 하나다. (#3404)

백엔드는 `Accept-Language` 를 읽지 않는다. 헤더가 없든 `ko` 든 `en` 이든 같은 한국어
문장을 준다. 갈래별 회귀는 각 영역 테스트에 있다 — 알림 목록
(`test_notification_template_api`), AI 코칭 카드(`test_ai_coach_feedback_korean_only`),
식단·운동 조언(`test_advice_korean_only`), 사진 분석
(`test_diet_analyze_display_name`), 주간 리포트 요약(`test_trainer_report_text`).

여기서는 어느 영역에도 속하지 않는 공통 자리를 본다.

  * 전역 500 응답의 안내 문장.
  * 언어 협상 코드가 앱에 다시 들어오지 않았는지(소스 검사, DB 없이 돈다).
  * 헤더를 보내는 클라이언트가 막히지 않는지 — 옛 앱은 계속 `Accept-Language` 를 보낸다.
"""
from __future__ import annotations

import re
from pathlib import Path

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.core import observability

_APP = Path(__file__).resolve().parents[1] / "app"

#: 옛 앱·브라우저가 보낼 수 있는 값. 어느 것이든 응답은 같다.
LANGUAGES = [None, "ko", "ko-KR", "en", "en-US,en;q=0.9", "ko;q=0.2, en;q=0.8", "fr", "*"]


def _headers(language: str | None) -> dict[str, str]:
    return {} if language is None else {"Accept-Language": language}


# ---- 전역 500 ----


@pytest.mark.parametrize("language", LANGUAGES)
def test_global_500_message_is_korean_whatever_the_header(language):
    app = FastAPI()
    observability.install(app)

    @app.get("/boom")
    def boom():
        raise RuntimeError("boom")

    client = TestClient(app, raise_server_exceptions=False)
    r = client.get("/boom", headers=_headers(language))
    assert r.status_code == 500
    assert r.json()["detail"] == "내부 서버 오류가 발생했어요."


# ---- 소스 ----


#: 요청 언어를 읽던 이름들. 앱 코드 어디에도 남지 않는다.
_RETIRED = re.compile(
    r"localized\(|current_locale|RequestLocale|get_request_locale|accept[-_]language",
    re.IGNORECASE,
)


def test_app_does_not_read_the_request_language():
    hits = []
    for path in sorted(_APP.rglob("*.py")):
        rel = path.relative_to(_APP).as_posix()
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if _RETIRED.search(line):
                hits.append(f"{rel}:{number}: {line.strip()}")
    assert hits == []


def test_locale_module_is_gone():
    assert not (_APP / "core" / "locale.py").exists()
    assert not (_APP / "services" / "recognizer" / "locale_prompt.py").exists()


# ---- 헤더를 보내는 클라이언트 (DB 필요) ----


@pytest.mark.parametrize("language", LANGUAGES)
def test_healthz_answers_whatever_the_header(client, language):
    r = client.get("/v1/healthz", headers=_headers(language))
    assert r.status_code == 200, r.text
    assert r.json()["status"] == "ok"


def test_preflight_still_allows_the_header(client):
    """옛 앱은 `Accept-Language` 를 계속 보낸다 — 사전 요청에서 막히면 안 된다."""
    r = client.options(
        "/v1/healthz",
        headers={
            "Origin": "http://localhost:3000",
            "Access-Control-Request-Method": "GET",
            "Access-Control-Request-Headers": "accept-language,authorization",
        },
    )
    if r.status_code == 400:
        pytest.skip("이 환경의 허용 출처에 localhost:3000 이 없다")
    assert r.status_code == 200, r.text
    assert "accept-language" in r.headers["access-control-allow-headers"].lower()


@pytest.mark.parametrize("language", LANGUAGES)
def test_unauthenticated_error_is_the_same_whatever_the_header(client, language):
    """오류 본문도 헤더를 따라 바뀌지 않는다."""
    plain = client.get("/v1/notifications")
    r = client.get("/v1/notifications", headers=_headers(language))
    assert r.status_code == plain.status_code == 401
    assert r.json() == plain.json()
