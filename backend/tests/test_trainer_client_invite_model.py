"""트레이너 담당 요청 모델의 상태 제약이 마이그레이션과 같다. (#3251)

마이그레이션 0050 이 만든 `ck_trainer_client_invite_status` 가 모델에 없어, `create_all`
로 만드는 DB 는 잘못된 상태값을 받았다. 모델과 마이그레이션의 식이 같은지 DB 없이 본다.
"""
from __future__ import annotations

import importlib.util
from pathlib import Path

from sqlalchemy import CheckConstraint

from app.models.models import TrainerClientInvite

_NAME = "ck_trainer_client_invite_status"
_MIGRATION = (
    Path(__file__).resolve().parent.parent
    / "migrations" / "versions" / "0050_trainer_client_invite.py"
)


def _migration_check_sql() -> str:
    """0050 의 `upgrade()` 가 만드는 CHECK 식. `op` 를 바꿔 끼워 인자만 받아 낸다."""
    spec = importlib.util.spec_from_file_location("m0050", _MIGRATION)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    found: list[str] = []

    class _Op:
        def create_table(self, name, *items):
            for item in items:
                if isinstance(item, CheckConstraint) and item.name == _NAME:
                    found.append(str(item.sqltext))

        def create_index(self, *args, **kwargs):
            pass

    module.op = _Op()
    module.upgrade()
    assert len(found) == 1
    return found[0]


def test_model_has_the_migration_status_check():
    checks = {
        c.name: str(c.sqltext)
        for c in TrainerClientInvite.__table__.constraints
        if isinstance(c, CheckConstraint)
    }
    assert checks.get(_NAME) == _migration_check_sql()
