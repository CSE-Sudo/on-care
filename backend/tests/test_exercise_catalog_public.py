"""운동 종목 참조표에 공공데이터 전건이 실려 있는가. (#1651)

큐레이션 60종만으로는 회원이 적는 이름을 다 받아 내지 못한다. 매칭 실패율이 곧
기능 실패율이라(#1312), 표에 무엇이 들어가는지가 곧 기능의 범위다. 여기서 지키는
것은 넷이다.

1. 공공데이터 원본이 **받은 그대로** 저장소에 있다 — 가공하면 KOGL 제4유형의
   변경금지에 걸린다.
2. 그 원본이 적재 행으로 읽힌다(인코딩·컬럼명이 바뀌면 조용히 빈 목록이 된다).
3. 큐레이션이 공공데이터보다 **먼저** 다 — 같은 이름이면 별칭까지 손질한 쪽이 남는다.
4. 유형은 적재할 때 이름으로 붙는다.
"""
from __future__ import annotations

from app.db.init_db import (
    PUBLIC_EXERCISE_CSV,
    _exercise_catalog_seed_rows,
    _public_exercise_rows,
    public_exercise_type,
)
from app.services.exercise_catalog.matcher import normalize


def test_공공데이터_원본이_저장소에_있다():
    assert PUBLIC_EXERCISE_CSV.exists(), (
        "원본이 없으면 표는 큐레이션 60종에 머문다"
    )


def test_원본이_적재_행으로_읽힌다():
    rows = _public_exercise_rows()
    # 원본 376행. 계수가 없거나 0 인 행만 빠진다.
    assert len(rows) > 300
    assert all(row["met"] > 0 for row in rows)
    assert {row["source"] for row in rows} == {"khpi"}


def test_큐레이션이_별칭까지_공공데이터보다_먼저다():
    rows = {row["name_norm"]: row for row in _exercise_catalog_seed_rows()}
    걷기 = rows[normalize("걷기")]
    assert 걷기["source"] == "curated"
    # 별칭은 큐레이션 쪽에만 있다 — 원본은 운동명과 계수 두 열뿐이다. 원본에도
    # 같은 이름이 있지만, 손질해 둔 별칭이 떨어져 나가면 안 된다.
    assert normalize("산책") in 걷기["aliases_norm"].split("|")
    assert normalize("산책") not in rows


def test_공공데이터만_있는_종목도_실린다():
    rows = {row["name_norm"]: row for row in _exercise_catalog_seed_rows()}
    # 큐레이션에 없는 이름. 원본에서 와야 한다 — 이런 종목이 붙지 않으면 회원이
    # 적은 이름은 유형 폴백으로 내려가 체중이 빠진 값이 적힌다.
    공공 = rows[normalize("스텝퍼")]
    assert 공공["source"] == "khpi"
    assert 공공["met"] > 0


def test_유형은_적재할_때_이름으로_붙는다():
    assert public_exercise_type("하타 요가") == "stretching"
    assert public_exercise_type("바벨 스쿼트") == "strength"
    assert public_exercise_type("빠르게 걷기") == "cardio"
    # 짐작이 안 되면 기타다. 틀린 유형으로 우겨 넣으면 주간 그래프가 틀어진다.
    assert public_exercise_type("다트") == "other"
