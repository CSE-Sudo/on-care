"""데모 시드가 만드는 계정·장소 id — 운영 필터와 정리 스크립트가 같은 목록을 본다. (#2811)

데모 시드(`SEED_DEMO_DATA=true`)는 실존하지 않는 트레이너·회원·헬스장을 만든다.
예전에는 기본값이 켜져 있어 운영 DB 에도 심겼을 수 있으므로,

- 트레이너 디렉터리(`gym_service`)는 데모가 꺼진 서버에서 이 트레이너들을 거르고,
- `scripts/purge_demo_data.py` 는 이 목록으로 이미 심긴 데이터를 지운다.

목록의 원본은 각 시드 모듈이다. 여기서 다시 적지 않고 모아서만 돌려준다 — 시드에
사람을 더하면 필터와 정리 대상에도 그대로 들어간다. 시드 모듈은 DB 세션 등을
불러오므로 함수 안에서 늦게 import 한다.
"""
from __future__ import annotations

from functools import lru_cache

from app.core.config import get_settings


def demo_data_enabled() -> bool:
    """이 서버가 데모 데이터를 보여 주는가 — 데모 시드가 켜진 비운영 서버만."""
    settings = get_settings()
    return settings.seed_demo_data and not settings.is_prod


@lru_cache
def demo_trainer_ids() -> frozenset[str]:
    """데모 트레이너 — 김태오(`seed_trainer`)와 헬스장 소속 가상 트레이너(`seed_gyms`)."""
    from app.db.seed_gyms import TRAINER_IDS
    from app.db.seed_trainer import TRAINER_ID

    return frozenset((TRAINER_ID, *TRAINER_IDS))


@lru_cache
def demo_member_ids() -> frozenset[str]:
    """데모 회원 — 김민수(회원 앱 데모 계정)와 담당 회원 15명(`seed_trainer`)."""
    from app.db.init_db import DEMO_USER_ID
    from app.db.seed_trainer import _MEMBERS

    return frozenset((DEMO_USER_ID, *(row[0] for row in _MEMBERS)))


def demo_user_ids() -> frozenset[str]:
    return demo_trainer_ids() | demo_member_ids()


@lru_cache
def demo_place_ids() -> frozenset[str]:
    """데모 장소 — 가상 헬스장(`seed_gyms`)과 데모 장소(`init_db.DEMO_PLACES`).

    실재 업체(카카오 place id)는 넣지 않는다. 실제 트레이너가 소속 헬스장 찾기
    (#2543)로 같은 업체를 골랐을 수 있어서다.
    """
    from app.db.init_db import DEMO_PLACES
    from app.db.seed_gyms import _DEMO_NONPARTNER_GYMS, _PARTNER_GYMS

    return frozenset(
        row[0] for row in (*_PARTNER_GYMS, *_DEMO_NONPARTNER_GYMS, *DEMO_PLACES)
    )
