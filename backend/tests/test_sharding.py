"""CI 테스트 묶음 규칙 — DB 불필요. (#3321)

묶음 규칙이 틀리면 잡은 모두 초록인데 어떤 테스트는 어느 잡에서도 돌지 않는다.
그 실패는 눈에 보이지 않으므로 규칙 자체를 여기서 본다.
"""
from __future__ import annotations

import random

import pytest

from tests import sharding


def _files(count: int, seed: int = 7) -> dict[str, int]:
    rng = random.Random(seed)
    return {f"tests/test_{i:03d}.py": rng.randint(1, 120) for i in range(count)}


@pytest.mark.parametrize("total", [1, 2, 3, 6, 8, 13])
def test_every_file_lands_in_exactly_one_shard(total):
    weights = _files(307)
    assignment = sharding.assign_shards(weights, total)
    assert set(assignment) == set(weights)
    assert set(assignment.values()) <= set(range(1, total + 1))


@pytest.mark.parametrize("total", [2, 6, 8])
def test_shards_together_cover_the_whole_suite(total):
    weights = _files(307)
    assignment = sharding.assign_shards(weights, total)
    per_shard = [
        sum(w for name, w in weights.items() if assignment[name] == shard)
        for shard in range(1, total + 1)
    ]
    assert sum(per_shard) == sum(weights.values())


def test_assignment_ignores_input_order():
    weights = _files(120)
    names = list(weights)
    random.Random(1).shuffle(names)
    shuffled = {name: weights[name] for name in names}
    assert sharding.assign_shards(weights, 6) == sharding.assign_shards(shuffled, 6)


def test_assignment_is_stable_across_calls():
    weights = _files(200)
    assert sharding.assign_shards(weights, 6) == sharding.assign_shards(dict(weights), 6)


@pytest.mark.parametrize("total", [2, 6, 8])
def test_shards_are_balanced_within_one_file(total):
    weights = _files(307)
    assignment = sharding.assign_shards(weights, total)
    loads = [0] * total
    for name, shard in assignment.items():
        loads[shard - 1] += weights[name]
    # 가장 가벼운 묶음에 넣는 규칙이라, 묶음 사이 차이는 파일 하나의 무게를 넘지 않는다.
    assert max(loads) - min(loads) <= max(weights.values())


def test_single_shard_keeps_everything():
    weights = _files(40)
    assert set(sharding.assign_shards(weights, 1).values()) == {1}


def test_more_shards_than_files_leaves_some_empty_but_loses_nothing():
    weights = {"tests/test_a.py": 3, "tests/test_b.py": 5}
    assignment = sharding.assign_shards(weights, 6)
    assert set(assignment) == set(weights)
    assert len(set(assignment.values())) == 2


def test_ties_break_by_name_then_lowest_shard():
    weights = {"tests/test_b.py": 4, "tests/test_a.py": 4, "tests/test_c.py": 4}
    assert sharding.assign_shards(weights, 3) == {
        "tests/test_a.py": 1,
        "tests/test_b.py": 2,
        "tests/test_c.py": 3,
    }


def test_no_files_gives_no_assignment():
    assert sharding.assign_shards({}, 6) == {}


@pytest.mark.parametrize("total", [0, -1])
def test_shard_count_must_be_positive(total):
    with pytest.raises(ValueError):
        sharding.assign_shards({"tests/test_a.py": 1}, total)


@pytest.mark.parametrize("value", [None, "", "   "])
def test_unset_means_no_sharding(value):
    assert sharding.parse_shard(value) is None


@pytest.mark.parametrize(
    ("value", "expected"),
    [("1/1", (1, 1)), ("2/6", (2, 6)), (" 6/6 ", (6, 6))],
)
def test_parse_reads_index_and_total(value, expected):
    assert sharding.parse_shard(value) == expected


@pytest.mark.parametrize("value", ["0/6", "7/6", "2", "2/", "/6", "a/b", "2/0", "-1/6", "1/6/2", "2 / 6"])
def test_parse_rejects_bad_values(value):
    with pytest.raises(ValueError):
        sharding.parse_shard(value)
