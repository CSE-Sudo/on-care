"""할 일 키 단위 병합 규칙 — DB 없이 순수 함수만. (#2886)

앱 `applyTaskKeyChange` 와 같은 규칙이어야 한다.
"""
from __future__ import annotations

import pytest

from app.schemas.trainer_api import TrainerTaskKeyChange
from app.services.trainer_task_progress_service import merge_key_change


def _merge(*, completed=(), pending=(), dismissed=(), previous_pending=(), **change):
    return merge_key_change(
        completed=set(completed),
        pending=set(pending),
        dismissed=set(dismissed),
        previous_pending=set(previous_pending),
        change=TrainerTaskKeyChange(**change),
    )


def test_check_adds_only_that_key_and_keeps_others():
    merged = _merge(
        completed={"a"}, pending={"b", "c"},
        key="b", action="check", keys=["a", "b", "c"], seen=["a", "b", "c"],
    )
    assert merged.completed == {"a", "b"}
    assert merged.pending == {"c"}
    assert merged.total == 3
    assert merged.completed_today == 2


def test_stale_screen_does_not_erase_other_check():
    # 화면은 a 가 체크된 걸 몰라도(옛 상태) b 만 보낸다 — a 는 남는다.
    merged = _merge(
        completed={"a"}, pending={"b"},
        key="b", action="check", keys=["a", "b"], seen=["a", "b"],
    )
    assert merged.completed == {"a", "b"}


def test_dismiss_is_one_way():
    merged = _merge(
        completed={"a"}, dismissed={"x"},
        key="a", action="dismiss", keys=["a", "x", "b"], seen=["a", "x", "b"],
    )
    assert merged.dismissed == {"a", "x"}
    assert "a" not in merged.completed
    assert merged.total == 1  # b 만 남는다.


def test_unseen_saved_keys_are_kept_and_seen_vanished_keys_dropped():
    merged = _merge(
        completed={"late", "gone"}, pending={"late-pending"},
        key="a", action="check", keys=["a"], seen=["a", "gone"],
    )
    assert merged.completed == {"late", "a"}
    assert merged.pending == {"late-pending"}
    assert merged.total == 3


def test_carried_over_split():
    merged = _merge(
        pending={"a", "b"}, previous_pending={"a"},
        key="a", action="check", keys=["a", "b"], seen=["a", "b"],
    )
    assert merged.completed_carried_over == 1
    assert merged.completed_today == 0


@pytest.mark.parametrize("action", ["check", "uncheck", "dismiss"])
def test_completed_never_exceeds_total(action):
    merged = _merge(
        completed={"a", "b", "c"}, pending=set(),
        key="a", action=action, keys=["a"], seen=["a", "b", "c"],
    )
    assert merged.completed_today + merged.completed_carried_over <= merged.total
