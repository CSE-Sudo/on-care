"""서비스 코드가 `app/core/clock.py` 를 우회해 현재 시각을 읽지 않는지 — DB 불필요 (#3452).

도메인 날짜는 `clock.now()`·`clock.today()` 로, 저장·만료 비교용 순간은
`clock.now_utc()` 로 읽는다. 한 곳이라도 `datetime.now(timezone.utc)` 를 직접 읽으면
테스트가 `clock.now` 를 고정해도 그 값만 실제 시각을 봐, 날짜와 순간이 어긋난 채
검증된다. 예전에는 46곳이 그랬다. 두 앱의 `test/core/utils/clock_test.dart` 와 같은
규율을 소스 검사로 지킨다.

주석·문서 문자열의 언급은 걸리지 않도록 소스를 AST 로 읽어 실제 호출만 찾는다.
"""
from __future__ import annotations

import ast
from pathlib import Path

APP = Path(__file__).resolve().parent.parent / "app"

#: 직접 읽어도 되는 곳과 그 이유. 경로는 `app/` 기준.
ALLOWED = {
    # 시계 자신이다.
    "core/clock.py": "실제 시각의 단일 원본",
    # 인증 토큰의 발급·만료·폐기. JWT 라이브러리가 `exp` 를 실제 시계로 검증하므로,
    # 여기를 고정 시계에 묶으면 시각을 고정한 테스트에서 토큰이 곧바로 만료된다.
    "core/security.py": "JWT 발급·검증은 실제 시각",
    "services/auth_tokens.py": "세션 만료 판정은 JWT 와 같은 실제 시각",
    "services/token_revocation.py": "토큰 폐기 기준은 JWT 와 같은 실제 시각",
}

#: (받는 이름, 메서드) — `datetime.now()`·`date.today()` 등.
BANNED = {
    ("datetime", "now"),
    ("datetime", "utcnow"),
    ("datetime", "today"),
    ("date", "today"),
}


def _direct_clock_calls(source: str) -> list[int]:
    lines: list[int] = []
    for node in ast.walk(ast.parse(source)):
        if not isinstance(node, ast.Call) or not isinstance(node.func, ast.Attribute):
            continue
        owner = node.func.value
        # `datetime.now()` 와 `datetime.datetime.now()` 를 모두 잡는다.
        name = owner.attr if isinstance(owner, ast.Attribute) else getattr(owner, "id", None)
        if (name, node.func.attr) in BANNED:
            lines.append(node.lineno)
    return sorted(lines)


def test_no_direct_clock_calls_outside_clock():
    leftovers = []
    for path in sorted(APP.rglob("*.py")):
        rel = path.relative_to(APP).as_posix()
        if rel in ALLOWED:
            continue
        for line in _direct_clock_calls(path.read_text(encoding="utf-8")):
            leftovers.append(f"app/{rel}:{line}")
    assert not leftovers, (
        "서버 시계를 직접 읽는 곳이 남았어요. clock.now()·clock.today()·clock.now_utc() 를 쓰세요:\n"
        + "\n".join(leftovers)
    )


def test_allowed_files_still_exist():
    for rel in ALLOWED:
        assert (APP / rel).is_file(), rel


def test_detector_finds_calls_but_not_mentions():
    source = '''
"""datetime.now() 를 쓰지 않는다."""
import datetime as dt
from datetime import date, datetime, timezone

# datetime.now(timezone.utc) 는 주석이다.
a = datetime.now(timezone.utc)
b = date.today()
c = dt.datetime.utcnow()
d = clock.now_utc()
'''
    assert _direct_clock_calls(source) == [7, 8, 9]
